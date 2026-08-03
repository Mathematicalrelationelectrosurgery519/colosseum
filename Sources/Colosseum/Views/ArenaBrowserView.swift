import AppKit
import AVFoundation
import SwiftData
import SwiftUI

struct ArenaBrowserView: View {
    let initialTarget: ArenaBrowseTarget
    /// Local board to save individual items into (optional).
    var destinationBoard: Board?
    var onClose: () -> Void
    var onImportedBoard: ((Board) -> Void)?

    @Environment(\.modelContext) private var context
    @State private var model = ArenaBrowserModel()
    @State private var stack: [ArenaBrowseTarget] = []
    @State private var selectedItem: ArenaContentItem?
    @State private var isImporting = false
    @State private var importProgress = ""
    @State private var statusMessage: String?
    @State private var hoverVideo: LoopingVideoPlayer?
    @State private var hoveringItemID: Int?
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: ColosseumTheme.cellMin, maximum: 260), spacing: ColosseumTheme.gridGap)]

    private var currentTarget: ArenaBrowseTarget {
        stack.last ?? initialTarget
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().overlay(ColosseumTheme.border)
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
            focused = true
            stack = [initialTarget]
            model.load(initialTarget)
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
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(ColosseumTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ColosseumTheme.elevated)
                    .padding(.bottom, 20)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if stack.count > 1 {
                Button {
                    pop()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ColosseumTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(model.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ColosseumTheme.primaryText)
                    Text("Are.na")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(ColosseumTheme.border, lineWidth: 1))
                }
                Text(model.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if isImporting {
                ProgressView()
                    .controlSize(.small)
                Text(importProgress)
                    .font(.caption)
                    .foregroundStyle(ColosseumTheme.secondaryText)
            }

            if let url = model.channel?.url {
                Button("Open on Are.na") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.bordered)
            }

            Button("Import Board") {
                Task { await importEntireBoard() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(isImporting || model.channel == nil)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(ColosseumTheme.secondaryText)
            .keyboardShortcut("w", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: ColosseumTheme.gridGap) {
                    ForEach(model.items) { item in
                        Button {
                            open(item)
                        } label: {
                            ArenaRemoteCell(
                                item: item,
                                isHovering: hoveringItemID == item.id,
                                hoverPlayer: hoveringItemID == item.id ? hoverVideo : nil
                            )
                        }
                        .buttonStyle(.plain)
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

                if model.isLoadingMore {
                    ProgressView()
                        .padding(.bottom, 28)
                } else if model.hasMore {
                    Button("Load more") {
                        model.loadMoreIfNeeded(currentItem: nil)
                    }
                    .padding(.bottom, 28)
                }
            }
        }
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
        model.load(target)
    }

    private func pop() {
        stopHover()
        guard stack.count > 1 else {
            onClose()
            return
        }
        withAnimation(ColosseumMotion.soft) {
            stack.removeLast()
            model.load(currentTarget)
        }
    }

    private func handleEscape() {
        if selectedItem != nil {
            withAnimation(ColosseumMotion.overlay) {
                selectedItem = nil
            }
        } else if stack.count > 1 {
            pop()
        } else {
            onClose()
        }
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
}

// MARK: - Grid cell

private struct ArenaRemoteCell: View {
    let item: ArenaContentItem
    var isHovering: Bool
    var hoverPlayer: LoopingVideoPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: item.kind == .channel || item.kind == .text ? 1 : 0.5))

            Text(item.displayTitle)
                .font(.system(size: 11))
                .foregroundStyle(ColosseumTheme.secondaryText)
                .lineLimit(1)
        }
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
                .foregroundStyle(ColosseumTheme.primaryText)
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
    @State private var isSaving = false
    @State private var statusMessage: String?
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
            Divider().overlay(ColosseumTheme.border)
            sidebar
                .frame(width: ColosseumTheme.sidebarWidth)
        }
        .background(ColosseumTheme.canvas)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            reloadPlayer()
        }
        .onChange(of: selected?.id) { _, _ in
            focused = true
            reloadPlayer()
        }
        .onExitCommand(perform: onClose)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-1)
            case .right: step(1)
            default: break
            }
        }
        // Keep arrow keys working even when AVPlayerView steals focus.
        .background {
            HStack {
                Button("", action: { step(-1) })
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("", action: { step(1) })
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
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
                        Text(item.displayTitle).font(.title)
                        if let owner = item.channelOwnerName {
                            Text("by \(owner)").foregroundStyle(ColosseumTheme.secondaryText)
                        }
                        Button("Browse Channel") { onOpenChannel(item) }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .disabled(items.isEmpty || index <= 0)
                    .help("Previous")
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .disabled(items.isEmpty || index >= items.count - 1)
                    .help("Next")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            .foregroundStyle(ColosseumTheme.secondaryText)
            .padding(16)

            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.displayTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ColosseumTheme.primaryText)

                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.system(size: 13))
                                .foregroundStyle(ColosseumTheme.secondaryText)
                        }

                        metaRow("Type", item.isVideo ? "video" : item.typeName.lowercased())
                        if item.imageWidth > 0 {
                            metaRow("Dimensions", "\(item.imageWidth) × \(item.imageHeight)")
                        }
                        if item.imageBytes > 0 {
                            metaRow("Size", ColosseumFormatters.byteCount(item.imageBytes))
                        } else if item.attachmentBytes > 0 {
                            metaRow("Size", ColosseumFormatters.byteCount(item.attachmentBytes))
                        }
                        if let source = item.sourceURL {
                            metaRow("Source", source)
                        }

                        Text("Remote preview — not stored locally")
                            .font(.caption)
                            .foregroundStyle(ColosseumTheme.tertiaryText)
                            .padding(.top, 4)

                        HStack(spacing: 8) {
                            if let destinationBoard {
                                Button(isSaving ? "Saving…" : "Save to Board") {
                                    Task { await save(item, to: destinationBoard) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.white)
                                .foregroundStyle(.black)
                                .disabled(isSaving)
                            }

                            Menu("Actions") {
                                if let urlString = item.previewURL ?? item.sourceURL,
                                   let url = URL(string: urlString) {
                                    Button("Open Original") { NSWorkspace.shared.open(url) }
                                }
                                if let urlString = item.sourceURL, let url = URL(string: urlString) {
                                    Button("Open Source URL") { NSWorkspace.shared.open(url) }
                                }
                            }
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(ColosseumTheme.secondaryText)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            Spacer(minLength: 0)
        }
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
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
    }

    private func remotePlaceholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(ColosseumTheme.secondaryText)
    }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
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

    private func save(_ item: ArenaContentItem, to board: Board) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await ArenaImportService.saveItem(item, into: board, context: context)
            statusMessage = "Saved to \(board.title)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
