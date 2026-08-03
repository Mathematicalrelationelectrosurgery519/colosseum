import AppKit
import AVFoundation
import SwiftData
import SwiftUI

struct ArenaBrowserView: View {
    let initialTarget: ArenaBrowseTarget
    @Binding var stack: [ArenaBrowseTarget]
    /// Local board to save individual items into (optional).
    var destinationBoard: Board?
    /// When false, host window toolbar shows the path (board-hosted). When true, draw matching chrome inline.
    var showsInlineChrome: Bool = true
    var onClose: () -> Void
    var onImportedBoard: ((Board) -> Void)?

    @Environment(\.modelContext) private var context
    @State private var model = ArenaBrowserModel()
    @State private var selectedItem: ArenaContentItem?
    @State private var isImporting = false
    @State private var importProgress = ""
    @State private var statusMessage: String?
    @State private var hoverVideo: LoopingVideoPlayer?
    @State private var hoveringItemID: Int?
    @State private var gridFocusID: Int?
    @State private var keyMonitor = KeyNavMonitor()
    @FocusState private var focused: Bool
    @AppStorage("boardColumnCount") private var columnCount = ChromeMetrics.boardColumnsDefault
    @State private var pinchBaseColumns: Int?
    @State private var lastPinchStep = 0
    @State private var isPinching = false
    @State private var pinchDidChange = false
    @State private var suppressGridClicksUntil: Date?

    private var isBrowsingGrid: Bool { selectedItem == nil }

    private var columns: [GridItem] {
        let count = min(max(columnCount, ChromeMetrics.boardColumnsMin), ChromeMetrics.boardColumnsMax)
        return Array(
            repeating: GridItem(.flexible(minimum: 72), spacing: ColosseumTheme.gridGap),
            count: count
        )
    }

    private var currentTarget: ArenaBrowseTarget {
        stack.last ?? initialTarget
    }

    private var pathSegments: [BoardPathSegment] {
        let source = stack.isEmpty ? [initialTarget] : stack
        return source.map {
            BoardPathSegment(
                id: $0.slug,
                title: ($0.title?.isEmpty == false ? $0.title! : $0.slug)
            )
        }
    }

    private var shouldSuppressGridClicks: Bool {
        if isPinching { return true }
        if let until = suppressGridClicksUntil, Date() < until { return true }
        return false
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if showsInlineChrome {
                    inlineChrome
                    Rectangle()
                        .fill(ColosseumTheme.border)
                        .frame(height: 1)
                }
                content
            }
            .background(ColosseumTheme.canvas)

            if selectedItem != nil {
                ArenaRemoteItemView(
                    items: model.items.filter { $0.kind != .channel },
                    selected: $selectedItem,
                    destinationBoard: destinationBoard,
                    onClose: {
                        withAnimation(ColosseumMotion.overlay) {
                            selectedItem = nil
                        }
                        activateFocus()
                    },
                    onOpenChannel: { item in
                        guard let slug = item.channelSlug else { return }
                        withAnimation(ColosseumMotion.overlay) {
                            push(ArenaBrowseTarget(
                                slug: slug,
                                title: item.title,
                                urlString: item.previewURL
                            ))
                            selectedItem = nil
                        }
                    }
                )
                .transition(ColosseumMotion.overlayTransition)
                .zIndex(20)
            }
        }
        .animation(ColosseumMotion.overlay, value: selectedItem?.id)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            if stack.isEmpty {
                stack = [initialTarget]
            }
            model.load(currentTarget)
            activateFocus()
        }
        .onDisappear { keyMonitor.remove() }
        .onChange(of: isBrowsingGrid) { _, browsing in
            if browsing { activateFocus() } else { keyMonitor.remove() }
        }
        .onChange(of: stack) { _, newStack in
            guard let last = newStack.last else { return }
            stopHover()
            selectedItem = nil
            model.load(last)
            gridFocusID = nil
            activateFocus()
        }
        .onChange(of: model.items.map(\.id)) { _, ids in
            if let gridFocusID, !ids.contains(gridFocusID) {
                self.gridFocusID = ids.first
            } else if gridFocusID == nil {
                gridFocusID = ids.first
            }
        }
        .onExitCommand(perform: handleEscape)
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
        .background {
            Button("", action: handleEscape)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumOpenCommand)) { _ in
            openOnArena()
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumArenaImport)) { _ in
            Task { await importEntireBoard() }
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(ColosseumTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ColosseumTheme.elevated)
                    .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
                    .padding(.bottom, 20)
            }
        }
        .highPriorityGesture(columnPinchGesture)
    }

    private var inlineChrome: some View {
        HStack(alignment: .center, spacing: 0) {
            BoardPathBreadcrumb(
                segments: pathSegments,
                currentColor: ColosseumTheme.remoteBoardTitle,
                onSegmentTap: jump(to:)
            )

            HStack(spacing: 10) {
                ShortcutHint(text: "⌘O")
                    .help("Open on Are.na")
                ShortcutHint(text: "⌘D")
                    .help("Import board")
            }
            .padding(.leading, 14)

            Spacer(minLength: 12)

            if isImporting {
                ProgressView()
                    .controlSize(.small)
                Text(importProgress)
                    .font(.caption)
                    .foregroundStyle(ColosseumTheme.secondaryText)
            }

            if isBrowsingGrid {
                ColumnDensityControl(columnCount: $columnCount)
            }
        }
        .padding(.horizontal, ChromeMetrics.contentInset)
        .frame(height: ChromeMetrics.controlHeight + 16)
        .background(ColosseumTheme.canvas)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading channel…")
                    .font(.callout)
                    .foregroundStyle(ColosseumTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage, model.items.isEmpty {
            VStack(spacing: 12) {
                Text("Couldn’t load channel")
                    .font(.headline)
                    .foregroundStyle(ColosseumTheme.primaryText)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(ColosseumTheme.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Retry") { model.load(currentTarget) }
                    .buttonStyle(ChromeButtonStyle(emphasized: true))
                    .pointingHandCursor()
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: ColosseumTheme.gridGap) {
                        ForEach(model.items) { item in
                            Button {
                                guard !shouldSuppressGridClicks else { return }
                                gridFocusID = item.id
                                open(item)
                            } label: {
                                ArenaRemoteCell(
                                    item: item,
                                    isHovering: hoveringItemID == item.id,
                                    hoverPlayer: hoveringItemID == item.id ? hoverVideo : nil
                                )
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .overlay {
                                if item.id == gridFocusID, isBrowsingGrid {
                                    Rectangle()
                                        .stroke(Color.white.opacity(0.85), lineWidth: 2)
                                        .allowsHitTesting(false)
                                }
                            }
                            .pointingHandCursor()
                            .onHover { hovering in
                                handleHover(item: item, hovering: hovering)
                            }
                            .onAppear {
                                model.loadMoreIfNeeded(currentItem: item)
                            }
                            .contextMenu {
                                if let destinationBoard {
                                    Button("Save to “\(destinationBoard.title)”") {
                                        Task { await save(item, to: destinationBoard) }
                                    }
                                }
                                if item.kind == .channel {
                                    Button("Browse Channel") { open(item) }
                                }
                                if let urlString = item.previewURL ?? item.sourceURL,
                                   let url = URL(string: urlString) {
                                    Button("Open Original") { NSWorkspace.shared.open(url) }
                                }
                            }
                        }
                    }
                    .padding(28)
                    .animation(ColosseumMotion.standard, value: columnCount)
                    .allowsHitTesting(!isPinching)

                    if model.isLoadingMore {
                        ProgressView()
                            .padding(.bottom, 28)
                    }
                }
                .onChange(of: gridFocusID) { _, id in
                    guard let id, isBrowsingGrid else { return }
                    withAnimation(ColosseumMotion.soft) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func activateFocus() {
        focused = true
        installKeyMonitor()
        DispatchQueue.main.async {
            focused = true
            if gridFocusID == nil {
                gridFocusID = model.items.first?.id
            }
        }
    }

    private func installKeyMonitor() {
        keyMonitor.onLeft = { moveGridFocus(delta: -1) }
        keyMonitor.onRight = { moveGridFocus(delta: 1) }
        keyMonitor.onUp = { moveGridFocus(delta: -columnCount) }
        keyMonitor.onDown = { moveGridFocus(delta: columnCount) }
        keyMonitor.onEnter = { activateFocusedItem() }
        keyMonitor.onEscape = {
            // Item detail (and its Connect sheet) owns Esc while open.
            if selectedItem != nil { return }
            handleEscape()
        }
        keyMonitor.shouldIgnoreNavigation = { !isBrowsingGrid }
        keyMonitor.install()
    }

    private func moveGridFocus(delta: Int) {
        guard isBrowsingGrid else { return }
        let items = model.items
        guard !items.isEmpty else { return }
        focused = true
        if let idx = items.firstIndex(where: { $0.id == gridFocusID }) {
            let next = idx + delta
            guard next >= 0, next < items.count else { return }
            withAnimation(ColosseumMotion.soft) {
                gridFocusID = items[next].id
            }
        } else {
            withAnimation(ColosseumMotion.soft) {
                gridFocusID = items[0].id
            }
        }
    }

    private func activateFocusedItem() {
        guard isBrowsingGrid else { return }
        let items = model.items
        let target = items.first(where: { $0.id == gridFocusID }) ?? items.first
        guard let item = target else { return }
        gridFocusID = item.id
        open(item)
    }

    private func open(_ item: ArenaContentItem) {
        if item.kind == .channel, let slug = item.channelSlug {
            withAnimation(ColosseumMotion.soft) {
                push(ArenaBrowseTarget(slug: slug, title: item.title, urlString: item.previewURL))
            }
            return
        }
        withAnimation(ColosseumMotion.overlay) {
            selectedItem = item
        }
    }

    private func push(_ target: ArenaBrowseTarget) {
        stopHover()
        stack.append(target)
    }

    private func jump(to index: Int) {
        guard index >= 0, index < stack.count else { return }
        withAnimation(ColosseumMotion.soft) {
            stack = Array(stack.prefix(index + 1))
        }
    }

    private func pop() {
        stopHover()
        guard stack.count > 1 else {
            onClose()
            return
        }
        _ = withAnimation(ColosseumMotion.soft) {
            stack.removeLast()
        }
    }

    private func handleEscape() {
        if selectedItem != nil {
            withAnimation(ColosseumMotion.overlay) {
                selectedItem = nil
            }
            return
        }
        if stack.count > 1 {
            pop()
        } else {
            onClose()
        }
    }

    private func openOnArena() {
        guard let url = model.channel?.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleHover(item: ArenaContentItem, hovering: Bool) {
        guard item.isVideo, let urlString = item.attachmentURL, let url = URL(string: urlString) else {
            if hoveringItemID == item.id { stopHover() }
            return
        }
        if hovering {
            stopHover()
            hoveringItemID = item.id
            let player = VideoPlayback.looping(url: url, muted: true)
            hoverVideo = player
            player.play()
        } else if hoveringItemID == item.id {
            stopHover()
        }
    }

    private func stopHover() {
        hoverVideo?.stop()
        hoverVideo = nil
        hoveringItemID = nil
    }

    private func save(_ item: ArenaContentItem, to board: Board) async {
        do {
            try await ArenaImportService.saveItem(item, into: board, context: context)
            statusMessage = "Saved to \(board.title)"
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == "Saved to \(board.title)" { statusMessage = nil }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importEntireBoard() async {
        guard let channel = model.channel else { return }
        isImporting = true
        importProgress = "Importing…"
        defer { isImporting = false }
        do {
            let board = try await ArenaImportService.importChannel(
                fromURLString: channel.url.absoluteString,
                context: context
            ) { progress in
                importProgress = progress.phase
            }
            onImportedBoard?(board)
            statusMessage = "Imported “\(board.title)”"
            try? await Task.sleep(for: .seconds(1.5))
            onClose()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var columnPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard isBrowsingGrid else { return }
                if pinchBaseColumns == nil {
                    isPinching = true
                    pinchDidChange = false
                    pinchBaseColumns = columnCount
                    lastPinchStep = 0
                }
                if abs(value - 1) > 0.04 {
                    pinchDidChange = true
                }
                let step = Int(((value - 1) / ChromeMetrics.pinchStepThreshold).rounded(.towardZero))
                guard step != lastPinchStep, let base = pinchBaseColumns else { return }
                lastPinchStep = step
                pinchDidChange = true
                let next = min(
                    max(base - step, ChromeMetrics.boardColumnsMin),
                    ChromeMetrics.boardColumnsMax
                )
                if next != columnCount {
                    withAnimation(ColosseumMotion.standard) {
                        columnCount = next
                    }
                }
            }
            .onEnded { _ in
                if pinchDidChange {
                    suppressGridClicksUntil = Date().addingTimeInterval(0.35)
                }
                isPinching = false
                pinchDidChange = false
                pinchBaseColumns = nil
                lastPinchStep = 0
            }
    }
}

// MARK: - Grid cell

private struct ArenaRemoteCell: View {
    let item: ArenaContentItem
    var isHovering: Bool
    var hoverPlayer: LoopingVideoPlayer?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if item.isVideo, isHovering, let hoverPlayer {
                    PlayerView(player: hoverPlayer.player, showsControls: false)
                        .allowsHitTesting(false)
                } else if item.kind == .text {
                    textCard
                } else if item.kind == .channel {
                    channelCard
                } else if let urlString = item.gridImageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            placeholder(systemName: "photo")
                        case .empty:
                            ProgressView().controlSize(.small)
                        @unknown default:
                            placeholder(systemName: "photo")
                        }
                    }
                } else if item.kind == .link {
                    placeholder(systemName: "link")
                } else {
                    placeholder(systemName: "square.dashed")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .background(ColosseumTheme.surface)

            if item.isVideo, !isHovering {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
            }
        }
        .overlay(
            Rectangle().stroke(
                ColosseumTheme.border,
                lineWidth: item.kind == .channel || item.kind == .text ? 1 : 0.5
            )
        )
    }

    private var textCard: some View {
        Text(item.textBody.isEmpty ? item.displayTitle : item.textBody)
            .font(.system(size: 12))
            .foregroundStyle(ColosseumTheme.primaryText)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(ColosseumTheme.canvas)
    }

    private var channelCard: some View {
        VStack(spacing: 6) {
            Text(item.displayTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ColosseumTheme.remoteBoardTitle)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let owner = item.channelOwnerName {
                Text("by \(owner)")
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.secondaryText)
            }
            Text("\(item.channelBlockCount) blocks")
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColosseumTheme.canvas)
    }

    private func placeholder(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(ColosseumTheme.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ColosseumTheme.surface)
    }
}

// MARK: - Item detail

private struct ArenaRemoteItemView: View {
    let items: [ArenaContentItem]
    @Binding var selected: ArenaContentItem?
    var destinationBoard: Board?
    var onClose: () -> Void
    var onOpenChannel: (ArenaContentItem) -> Void

    @Environment(\.modelContext) private var context
    @State private var loopingPlayer: LoopingVideoPlayer?
    @State private var showConnect = false
    @State private var showMeta = false
    @State private var statusMessage: String?
    @State private var keyMonitor = KeyNavMonitor()
    @FocusState private var focused: Bool

    private var index: Int {
        guard let selected else { return 0 }
        return items.firstIndex(where: { $0.id == selected.id }) ?? 0
    }

    private var item: ArenaContentItem? { selected }

    var body: some View {
        HStack(spacing: 0) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            Divider().overlay(ColosseumTheme.border)
            sidebar
                .frame(width: ColosseumTheme.sidebarWidth)
        }
        .background(ColosseumTheme.canvas)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 10) {
                ShortcutHint(text: "←")
                ShortcutHint(text: "→")
                ShortcutHint(text: "esc")
            }
            .padding(16)
            .allowsHitTesting(false)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            reloadPlayer()
            installKeyMonitor()
        }
        .onDisappear { keyMonitor.remove() }
        .onChange(of: selected?.id) { _, _ in
            focused = true
            showMeta = false
            reloadPlayer()
        }
        .onChange(of: showConnect) { _, _ in
            installKeyMonitor()
        }
        .onExitCommand(perform: handleEscape)
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
        .sheet(isPresented: $showConnect) {
            if let item {
                ConnectSheet(
                    block: nil,
                    nestedBoard: nil,
                    remoteItem: item,
                    excludeBoardID: nil
                )
            }
        }
    }

    private func installKeyMonitor() {
        keyMonitor.onLeft = { step(-1) }
        keyMonitor.onRight = { step(1) }
        keyMonitor.onEscape = { handleEscape() }
        keyMonitor.shouldIgnoreNavigation = { showConnect }
        keyMonitor.install()
    }

    private func handleEscape() {
        if showConnect {
            showConnect = false
            return
        }
        onClose()
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            ColosseumTheme.canvas
            if let item {
                switch item.kind {
                case .image, .link, .attachment, .other:
                    if item.isVideo, let loopingPlayer {
                        PlayerView(player: loopingPlayer.player)
                            .padding(24)
                    } else if let urlString = item.imageURL ?? item.gridImageURL,
                              let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(24)
                            case .failure:
                                remotePlaceholder("Couldn’t load image")
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else if item.kind == .link {
                        linkPlaceholder(item)
                    } else {
                        remotePlaceholder(item.displayTitle)
                    }
                case .text:
                    ScrollView {
                        Text(item.textBody.isEmpty ? item.displayTitle : item.textBody)
                            .font(.system(size: 18))
                            .foregroundStyle(ColosseumTheme.primaryText)
                            .frame(maxWidth: 640, alignment: .leading)
                            .padding(40)
                    }
                case .channel:
                    VStack(spacing: 12) {
                        Text(item.displayTitle)
                            .font(.title)
                            .foregroundStyle(ColosseumTheme.remoteBoardTitle)
                        if let owner = item.channelOwnerName {
                            Text("by \(owner)").foregroundStyle(ColosseumTheme.secondaryText)
                        }
                        Button("Browse Channel") { onOpenChannel(item) }
                            .buttonStyle(ChromeButtonStyle(emphasized: true))
                            .pointingHandCursor()
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.system(size: 13))
                                .foregroundStyle(ColosseumTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("notes…")
                                .font(.system(size: 13))
                                .foregroundStyle(ColosseumTheme.tertiaryText)
                        }

                        if item.kind == .text, !item.textBody.isEmpty {
                            Text(item.textBody)
                                .font(.system(size: 13))
                                .foregroundStyle(ColosseumTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(ColosseumTheme.surface)
                                .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 0.5))
                        }

                        actionRow(for: item)
                            .overlay(alignment: .topTrailing) {
                                if showMeta {
                                    remoteMetaOverlay(for: item)
                                        .fixedSize()
                                        .offset(y: 36)
                                        .transition(ColosseumMotion.fade)
                                }
                            }
                            .zIndex(2)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(ColosseumTheme.secondaryText)
                        }

                        Text("Remote preview — not stored locally")
                            .font(.caption)
                            .foregroundStyle(ColosseumTheme.tertiaryText)
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            Spacer(minLength: 0)
        }
        .background(ColosseumTheme.canvas)
    }

    @ViewBuilder
    private func actionRow(for item: ArenaContentItem) -> some View {
        HStack(spacing: 8) {
            Button("Connect →") { showConnect = true }
                .buttonStyle(ChromeButtonStyle(emphasized: true))
                .pointingHandCursor()

            if let source = item.sourceURL ?? item.previewURL, let url = URL(string: source) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(ChromeIconButtonStyle())
                .help("Open Source URL")
                .pointingHandCursor()
            }

            if item.kind == .channel,
               let slug = item.channelSlug {
                let owner = item.channelOwnerSlug ?? "are.na"
                if let url = URL(string: "https://www.are.na/\(owner)/\(slug)") {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(ChromeIconButtonStyle())
                    .help("Open on Are.na")
                    .pointingHandCursor()
                }
            }

            Button {
                withAnimation(ColosseumMotion.soft) {
                    showMeta.toggle()
                }
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(ChromeIconButtonStyle(active: showMeta))
            .help("Metadata")
            .pointingHandCursor()
            .onHover { hovering in
                withAnimation(ColosseumMotion.soft) {
                    showMeta = hovering
                }
            }
        }
    }

    @ViewBuilder
    private func remoteMetaOverlay(for item: ArenaContentItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    item.kind == .channel
                        ? ColosseumTheme.remoteBoardTitle
                        : ColosseumTheme.primaryText
                )

            VStack(spacing: 0) {
                metaRow("Content Type", item.isVideo ? "video" : item.typeName.lowercased())
                if item.imageWidth > 0, item.imageHeight > 0 {
                    metaRow("Dimensions", "\(item.imageWidth) × \(item.imageHeight)")
                }
                if item.imageBytes > 0 {
                    metaRow("File Size", ColosseumFormatters.byteCount(item.imageBytes))
                } else if item.attachmentBytes > 0 {
                    metaRow("File Size", ColosseumFormatters.byteCount(item.attachmentBytes))
                }
                if item.kind == .channel {
                    metaRow("Blocks", "\(item.channelBlockCount)")
                    if let owner = item.channelOwnerName {
                        metaRow("By", owner)
                    }
                }
                if let source = item.sourceURL, !source.isEmpty {
                    metaRow("Source", source)
                }
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(ColosseumTheme.elevated)
        .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .allowsHitTesting(true)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(ColosseumTheme.tertiaryText)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(ColosseumTheme.primaryText)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ColosseumTheme.border).frame(height: 0.5)
        }
    }

    private func linkPlaceholder(_ item: ArenaContentItem) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ColosseumTheme.secondaryText)
            Text(item.displayTitle)
                .font(.title2)
                .foregroundStyle(ColosseumTheme.primaryText)
            if let source = item.sourceURL, let url = URL(string: source) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
                    .buttonStyle(ChromeButtonStyle(emphasized: true))
                    .pointingHandCursor()
            }
        }
    }

    private func remotePlaceholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(ColosseumTheme.secondaryText)
    }

    private func step(_ delta: Int) {
        guard !showConnect, !items.isEmpty else { return }
        let next = index + delta
        guard next >= 0, next < items.count else { return }
        selected = items[next]
        focused = true
    }

    private func reloadPlayer() {
        loopingPlayer?.stop()
        loopingPlayer = nil
        guard let item, item.isVideo, let urlString = item.attachmentURL, let url = URL(string: urlString) else {
            return
        }
        let next = VideoPlayback.looping(url: url, muted: false)
        loopingPlayer = next
        next.play()
    }
}
