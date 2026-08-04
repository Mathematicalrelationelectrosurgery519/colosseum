import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BoardOverviewView: View {
    @Bindable var board: Board
    @Binding var path: [UUID]

    @Environment(\.modelContext) private var context
    @Query(sort: \Board.updatedAt, order: .reverse) private var allBoards: [Board]

    @State private var selectedConnectionID: UUID?
    @State private var arenaBrowseTarget: ArenaBrowseTarget?
    @State private var arenaStack: [ArenaBrowseTarget] = []
    @State private var showAddSheet = false
    @State private var showRename = false
    @State private var renameTitle = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var isTargeted = false
    @State private var selectedTags: Set<String> = []
    @State private var tagSelectionOrder: [String] = []
    @State private var tagMatchMode: TagMatchMode = .intersection
    @AppStorage("boardColumnCount") private var columnCount = ChromeMetrics.boardColumnsDefault
    @State private var pinchBaseColumns: Int?
    @State private var lastPinchStep = 0
    @State private var isPinching = false
    @State private var pinchDidChange = false
    @State private var suppressGridClicksUntil: Date?
    @State private var gridFocusID: UUID?
    @State private var boardKeyMonitor = KeyNavMonitor()
    @FocusState private var boardFocused: Bool
    /// Keyboard tag-assign: T focuses the block, popover for multi-select; Esc exits.
    @State private var isAssigningTag = false
    @State private var tagAssignFocusIndex = 0
    /// Soft-removed connections that can be restored with undo (max 3).
    @State private var removalUndoStack: [RemovalUndoEntry] = []

    private struct RemovalUndoEntry {
        let boardID: UUID
        let position: Int
        let blockID: UUID?
        let nestedBoardID: UUID?
    }

    private var isBrowsingGrid: Bool {
        selectedConnectionID == nil && arenaBrowseTarget == nil
    }

    private var pathSegments: [BoardPathSegment] {
        path.compactMap { id in
            guard let match = allBoards.first(where: { $0.id == id }) else { return nil }
            return BoardPathSegment(id: id.uuidString, title: match.title)
        }
    }

    private var arenaPathSegments: [BoardPathSegment] {
        arenaStack.map {
            BoardPathSegment(id: $0.slug, title: $0.title?.isEmpty == false ? $0.title! : $0.slug)
        }
    }

    private var tagAssignConnection: Connection? {
        guard isAssigningTag, let gridFocusID else { return nil }
        return connections.first(where: { $0.id == gridFocusID })
    }

    private var tagAssignSelectedKeys: Set<String> {
        guard let connection = tagAssignConnection else { return [] }
        return TagParser.tags(for: connection)
    }

    private var focusedAssignTagKey: String? {
        guard isAssigningTag, availableTags.indices.contains(tagAssignFocusIndex) else { return nil }
        return TagParser.normalize(availableTags[tagAssignFocusIndex])
    }

    private var shouldSuppressGridClicks: Bool {
        if isAssigningTag { return true }
        if isPinching { return true }
        if let until = suppressGridClicksUntil, Date() < until { return true }
        return false
    }

    private var columns: [GridItem] {
        let count = min(max(columnCount, ChromeMetrics.boardColumnsMin), ChromeMetrics.boardColumnsMax)
        return Array(
            repeating: GridItem(.flexible(minimum: 72), spacing: ColosseumTheme.gridGap),
            count: count
        )
    }

    private var connections: [Connection] {
        board.sortedConnections
    }

    private var availableTags: [String] {
        TagParser.boardTags(from: board)
    }

    private var filteredConnections: [Connection] {
        guard !selectedTags.isEmpty else { return connections }
        return connections.filter {
            TagParser.matches(connection: $0, selected: selectedTags, mode: tagMatchMode)
        }
    }

    private var selectedConnection: Connection? {
        connections.first(where: { $0.id == selectedConnectionID })
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    var body: some View {
        applyBoardInteractions(to: applyBoardChrome(to: boardStack))
    }

    private func applyBoardChrome<V: View>(to view: V) -> some View {
        view
            .animation(ColosseumMotion.overlay, value: selectedConnectionID)
            .animation(ColosseumMotion.overlay, value: arenaBrowseTarget?.slug)
            .navigationTitle("")
            .toolbarBackground(ColosseumTheme.canvas, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarColorScheme(.dark, for: .windowToolbar)
            .toolbar {
                if arenaBrowseTarget != nil {
                    ColosseumBoardHeaderToolbar(
                        segments: arenaPathSegments.isEmpty
                            ? [BoardPathSegment(id: "arena", title: "Are.na")]
                            : arenaPathSegments,
                        currentColor: ColosseumTheme.remoteBoardTitle,
                        onSegmentTap: jumpArenaStack(to:),
                        shortcutHints: [
                            ShortcutHintItem(text: "⌘O", help: "Open on Are.na"),
                            ShortcutHintItem(text: "⌘D", help: "Import board"),
                        ]
                    )
                } else {
                    ColosseumBoardHeaderToolbar(
                        segments: pathSegments.isEmpty
                            ? [BoardPathSegment(id: board.id.uuidString, title: board.title)]
                            : pathSegments,
                        onSegmentTap: navigateToPathIndex(_:)
                    )
                }
                if !availableTags.isEmpty {
                    ToolbarItem(placement: .principal) {
                        TagHeaderScroller(
                            tags: availableTags,
                            selected: $selectedTags,
                            selectionOrder: $tagSelectionOrder
                        )
                        .opacity(isBrowsingGrid && !isAssigningTag ? 1 : 0)
                        .allowsHitTesting(isBrowsingGrid && !isAssigningTag)
                        .animation(ColosseumMotion.overlay, value: isBrowsingGrid)
                        .animation(ColosseumMotion.overlay, value: isAssigningTag)
                    }
                    .colosseumPlainToolbarItem()
                }
                ColosseumColumnSliderToolbar(
                    columnCount: $columnCount,
                    tagMatchMode: $tagMatchMode,
                    showTagMode: !availableTags.isEmpty && arenaBrowseTarget == nil,
                    isImporting: isImporting,
                    visible: (isBrowsingGrid || arenaBrowseTarget != nil) && !isAssigningTag
                )
            }
    }

    private func applyBoardInteractions<V: View>(to view: V) -> some View {
        view
            .background {
                Group {
                    Button("") {
                        renameTitle = board.title
                        showRename = true
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    Button("") { setTagMatchMode(.intersection) }
                        .keyboardShortcut("n", modifiers: [])
                    Button("") { setTagMatchMode(.union) }
                        .keyboardShortcut("u", modifiers: [])
                }
                .opacity(0)
                .allowsHitTesting(false)
            }
            .focusable()
            .focused($boardFocused)
            .focusEffectDisabled()
            .onAppear { activateBoardFocus() }
            .onDisappear {
                boardKeyMonitor.remove()
                while let entry = removalUndoStack.popLast() {
                    finalizeOrphan(from: entry)
                }
            }
            .onChange(of: isBrowsingGrid) { _, browsing in
                if browsing {
                    activateBoardFocus()
                } else {
                    endTagAssign()
                    boardKeyMonitor.remove()
                }
            }
            .onChange(of: filteredConnections.map(\.id)) { _, ids in
                if let gridFocusID, !ids.contains(gridFocusID) {
                    self.gridFocusID = ids.first
                }
            }
            .onChange(of: availableTags) { _, tags in
                let keys = Set(tags.map { TagParser.normalize($0) })
                selectedTags = selectedTags.intersection(keys)
                tagSelectionOrder = tagSelectionOrder.filter { keys.contains($0) }
                if isAssigningTag {
                    if tags.isEmpty {
                        endTagAssign()
                    } else {
                        tagAssignFocusIndex = min(tagAssignFocusIndex, max(0, tags.count - 1))
                    }
                }
            }
            .onExitCommand(perform: handleEscape)
            .sheet(isPresented: $showAddSheet) {
                AddContentSheet(board: board)
            }
            .alert("Rename Board", isPresented: $showRename) {
                TextField("Title", text: $renameTitle)
                Button("Save") {
                    board.title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? board.title : renameTitle
                    board.updatedAt = .now
                    try? context.save()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onDrop(of: [.fileURL, .url, .plainText, .image, .png, .tiff], isTargeted: $isTargeted) { providers in
                _ = handleDrop(providers)
                return true
            }
            .overlay {
                if isTargeted {
                    Rectangle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumAdd)) { _ in
                showAddSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumRename)) { _ in
                renameTitle = board.title
                showRename = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumColumnsIncrease)) { _ in
                adjustColumns(by: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumColumnsDecrease)) { _ in
                adjustColumns(by: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumPaste)) { _ in
                Task { await paste() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumOpenCommand)) { _ in
                guard arenaBrowseTarget == nil else { return }
                openFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumOpenFiles)) { _ in
                guard arenaBrowseTarget == nil else { return }
                openFiles()
            }
            .alert("Import Error", isPresented: importErrorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func setTagMatchMode(_ mode: TagMatchMode) {
        guard isBrowsingGrid, tagMatchMode != mode else { return }
        withAnimation(ColosseumMotion.soft) {
            tagMatchMode = mode
        }
    }

    private func selectOnlyTag(_ tag: String) {
        let key = TagParser.normalize(tag)
        selectedTags = [key]
        tagSelectionOrder = [key]
    }

    private func activateBoardFocus() {
        boardFocused = true
        installBoardKeyMonitor()
        // Defer one tick so SwiftUI finishes mounting after the home → board fade.
        DispatchQueue.main.async {
            boardFocused = true
            if gridFocusID == nil {
                gridFocusID = filteredConnections.first?.id
            }
        }
    }

    private func installBoardKeyMonitor() {
        boardKeyMonitor.onLeft = {
            if isAssigningTag {
                moveTagAssignFocus(delta: -1)
            } else {
                moveGridFocus(delta: -1)
            }
        }
        boardKeyMonitor.onRight = {
            if isAssigningTag {
                moveTagAssignFocus(delta: 1)
            } else {
                moveGridFocus(delta: 1)
            }
        }
        boardKeyMonitor.onUp = {
            if isAssigningTag {
                moveTagAssignFocus(delta: -1)
            } else {
                moveGridFocus(delta: -columnCount)
            }
        }
        boardKeyMonitor.onDown = {
            if isAssigningTag {
                moveTagAssignFocus(delta: 1)
            } else {
                moveGridFocus(delta: columnCount)
            }
        }
        boardKeyMonitor.onEnter = {
            if isAssigningTag {
                toggleFocusedAssignTag()
            } else {
                activateFocusedConnection()
            }
        }
        boardKeyMonitor.onTab = { false }
        boardKeyMonitor.onEscape = {
            if isAssigningTag {
                endTagAssign()
            } else if arenaBrowseTarget != nil {
                // ArenaBrowserView owns Esc while remote is open.
                return
            } else if selectedConnectionID != nil {
                // BlockView owns Esc (including Connect sheet).
                return
            } else {
                handleEscape()
            }
        }
        boardKeyMonitor.onDelete = {
            guard isBrowsingGrid, !isAssigningTag else { return }
            deleteFocusedConnection()
        }
        boardKeyMonitor.onUndo = {
            guard isBrowsingGrid, !isAssigningTag else { return false }
            return undoLastRemoval()
        }
        boardKeyMonitor.onCopy = {
            guard isBrowsingGrid, !isAssigningTag else { return false }
            return copyFocusedBlock()
        }
        boardKeyMonitor.onCharacter = { char in
            guard isBrowsingGrid else { return false }
            if char == "t" {
                DispatchQueue.main.async { toggleTagAssign() }
                return true
            }
            return false
        }
        boardKeyMonitor.shouldIgnoreNavigation = { !isBrowsingGrid }
        boardKeyMonitor.install()
    }

    @discardableResult
    private func copyFocusedBlock() -> Bool {
        guard let focusID = gridFocusID,
              let block = filteredConnections.first(where: { $0.id == focusID })?.block
        else { return false }
        return BlockClipboard.copy(block)
    }

    private func deleteFocusedConnection() {
        guard let focusID = gridFocusID,
              let index = filteredConnections.firstIndex(where: { $0.id == focusID })
        else { return }

        let connection = filteredConnections[index]
        let entry = RemovalUndoEntry(
            boardID: board.id,
            position: connection.position,
            blockID: connection.block?.id,
            nestedBoardID: connection.nestedBoard?.id
        )

        // Soft-remove so undo can reconnect without restoring media from disk.
        ImportService.removeConnection(connection, deleteOrphanedBlock: false, context: context)
        pushRemovalUndo(entry)
        try? context.save()

        let remaining = filteredConnections
        if remaining.isEmpty {
            gridFocusID = nil
        } else if index < remaining.count {
            gridFocusID = remaining[index].id
        } else {
            gridFocusID = remaining[remaining.count - 1].id
        }
    }

    private func pushRemovalUndo(_ entry: RemovalUndoEntry) {
        removalUndoStack.append(entry)
        while removalUndoStack.count > 3 {
            let dropped = removalUndoStack.removeFirst()
            finalizeOrphan(from: dropped)
        }
    }

    @discardableResult
    private func undoLastRemoval() -> Bool {
        guard let entry = removalUndoStack.popLast() else { return false }
        let targetBoard = entry.boardID == board.id
            ? board
            : allBoards.first(where: { $0.id == entry.boardID })
        guard let targetBoard else {
            finalizeOrphan(from: entry)
            return true
        }

        let block: Block? = {
            guard let id = entry.blockID else { return nil }
            return try? context.fetch(
                FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })
            ).first
        }()
        let nested: Board? = entry.nestedBoardID.flatMap { id in
            allBoards.first(where: { $0.id == id })
        }

        guard block != nil || nested != nil else { return true }

        ImportService.reconnect(
            block: block,
            nestedBoard: nested,
            to: targetBoard,
            position: entry.position,
            context: context
        )
        try? context.save()

        if targetBoard.id == board.id {
            if let block {
                gridFocusID = board.connections.first(where: { $0.block?.id == block.id })?.id
            } else if let nested {
                gridFocusID = board.connections.first(where: { $0.nestedBoard?.id == nested.id })?.id
            }
        }
        return true
    }

    private func finalizeOrphan(from entry: RemovalUndoEntry) {
        guard let id = entry.blockID else { return }
        guard let block = try? context.fetch(
            FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        ImportService.deleteOrphanedBlockIfNeeded(block, context: context)
        try? context.save()
    }

    private func toggleTagAssign() {
        if isAssigningTag {
            endTagAssign()
            return
        }
        beginTagAssign()
    }

    private func beginTagAssign() {
        guard isBrowsingGrid, !availableTags.isEmpty else { return }
        if gridFocusID == nil {
            gridFocusID = filteredConnections.first?.id
        }
        guard gridFocusID != nil else { return }
        boardFocused = true
        tagAssignFocusIndex = 0
        withAnimation(ColosseumMotion.overlay) {
            isAssigningTag = true
        }
    }

    private func endTagAssign() {
        withAnimation(ColosseumMotion.overlay) {
            isAssigningTag = false
        }
        tagAssignFocusIndex = 0
        boardFocused = true
    }

    private func moveTagAssignFocus(delta: Int) {
        guard isAssigningTag else { return }
        let tags = availableTags
        guard !tags.isEmpty else { return }
        let count = tags.count
        let next = ((tagAssignFocusIndex + delta) % count + count) % count
        withAnimation(ColosseumMotion.soft) {
            tagAssignFocusIndex = next
        }
    }

    private func toggleFocusedAssignTag() {
        guard availableTags.indices.contains(tagAssignFocusIndex) else { return }
        toggleAssignTag(availableTags[tagAssignFocusIndex])
    }

    private func moveGridFocus(delta: Int) {
        guard isBrowsingGrid else { return }
        let items = filteredConnections
        guard !items.isEmpty else { return }
        boardFocused = true
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

    private func activateFocusedConnection() {
        guard isBrowsingGrid else { return }
        let items = filteredConnections
        let target = items.first(where: { $0.id == gridFocusID }) ?? items.first
        guard let connection = target else { return }
        gridFocusID = connection.id
        openConnection(connection)
    }

    private func openConnection(_ connection: Connection) {
        if let nested = connection.nestedBoard {
            withAnimation(ColosseumMotion.overlay) {
                path.append(nested.id)
            }
        } else if let block = connection.block {
            if block.kind == .arenaChannel {
                openArenaBrowser(for: block)
            } else {
                withAnimation(ColosseumMotion.overlay) {
                    selectedConnectionID = connection.id
                }
            }
        }
    }

    private var boardStack: some View {
        ZStack {
            boardGrid
                .background(ColosseumTheme.canvas)

            if let connection = selectedConnection, let block = connection.block, block.kind != .arenaChannel {
                BlockView(
                    board: board,
                    connections: connections.filter { $0.block != nil && $0.block?.kind != .arenaChannel },
                    selectedID: $selectedConnectionID,
                    onClose: {
                        withAnimation(ColosseumMotion.overlay) {
                            selectedConnectionID = nil
                        }
                        activateBoardFocus()
                    },
                    onTagTap: { tag in
                        withAnimation(ColosseumMotion.overlay) {
                            selectedConnectionID = nil
                            selectOnlyTag(tag)
                        }
                    }
                )
                .transition(ColosseumMotion.overlayTransition)
                .zIndex(10)
            }

            if let arenaBrowseTarget {
                ArenaBrowserView(
                    initialTarget: arenaBrowseTarget,
                    stack: $arenaStack,
                    destinationBoard: board,
                    showsInlineChrome: false,
                    onClose: {
                        withAnimation(ColosseumMotion.overlay) {
                            self.arenaBrowseTarget = nil
                            arenaStack = []
                        }
                    },
                    onImportedBoard: { imported in
                        withAnimation(ColosseumMotion.overlay) {
                            self.arenaBrowseTarget = nil
                            arenaStack = []
                            path.append(imported.id)
                        }
                    }
                )
                .transition(ColosseumMotion.overlayTransition)
                .zIndex(20)
            }
        }
    }

    private var boardGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: ColosseumTheme.gridGap) {
                    Button {
                        guard !shouldSuppressGridClicks else { return }
                        showAddSheet = true
                    } label: {
                        AddBlockCell()
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()

                    ForEach(filteredConnections, id: \.id) { connection in
                        let isFocus = connection.id == gridFocusID
                        connectionCell(connection)
                            .id(connection.id)
                            .anchorPreference(key: TagAssignAnchorKey.self, value: .bounds) {
                                isAssigningTag && isFocus ? $0 : nil
                            }
                            .gridSelectionRing(isActive: isFocus && isBrowsingGrid && !isAssigningTag)
                            .pointingHandCursor()
                            .transition(ColosseumMotion.itemTransition)
                    }
                }
                .padding(28)
                .padding(.bottom, isAssigningTag ? 200 : 0)
                .animation(ColosseumMotion.standard, value: selectedTags)
                .animation(ColosseumMotion.standard, value: tagMatchMode)
                .animation(ColosseumMotion.soft, value: filteredConnections.map(\.id))
                .animation(ColosseumMotion.standard, value: columnCount)
                .allowsHitTesting(!isPinching && !isAssigningTag)
            }
            .blur(radius: isAssigningTag ? 5 : 0)
            .overlay {
                if isAssigningTag {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { endTagAssign() }
                        .transition(.opacity)
                }
            }
            .overlayPreferenceValue(TagAssignAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    if isAssigningTag, let anchor, let connection = tagAssignConnection {
                        let rect = proxy[anchor]
                        tagAssignElevated(connection: connection, rect: rect)
                            .transition(ColosseumMotion.overlayTransition)
                    }
                }
                .allowsHitTesting(isAssigningTag)
            }
            .onChange(of: gridFocusID) { _, id in
                guard let id, isBrowsingGrid else { return }
                withAnimation(ColosseumMotion.soft) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: isAssigningTag) { _, assigning in
                guard assigning, let id = gridFocusID else { return }
                withAnimation(ColosseumMotion.soft) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .highPriorityGesture(columnPinchGesture)
        .animation(ColosseumMotion.overlay, value: isAssigningTag)
    }

    @ViewBuilder
    private func tagAssignElevated(connection: Connection, rect: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            connectionCellContent(connection)
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .gridSelectionRing(isActive: true)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

            TagAssignPopover(
                tags: availableTags,
                selectedKeys: tagAssignSelectedKeys,
                focusedKey: focusedAssignTagKey,
                onToggle: { toggleAssignTag($0) }
            )
            .frame(width: max(rect.width, 160), alignment: .leading)
        }
        .frame(width: rect.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .offset(x: rect.minX, y: rect.minY)
    }

    private func toggleAssignTag(_ tag: String) {
        guard isAssigningTag,
              let connection = tagAssignConnection
        else { return }
        let key = TagParser.normalize(tag)
        if let idx = availableTags.firstIndex(where: { TagParser.normalize($0) == key }) {
            tagAssignFocusIndex = idx
        }
        applyTagToggle(tag, on: connection, currentlyOn: TagParser.tags(for: connection).contains(key))
    }

    private func applyTagToggle(_ tag: String, on connection: Connection, currentlyOn: Bool) {
        if let block = connection.block {
            block.notes = currentlyOn
                ? TagParser.removingTag(tag, from: block.notes)
                : TagParser.appendingTag(tag, to: block.notes)
            board.updatedAt = .now
            try? context.save()
        } else if let nested = connection.nestedBoard {
            nested.notes = currentlyOn
                ? TagParser.removingTag(tag, from: nested.notes)
                : TagParser.appendingTag(tag, to: nested.notes)
            nested.updatedAt = .now
            board.updatedAt = .now
            try? context.save()
        }
    }

    @ViewBuilder
    private func connectionCell(_ connection: Connection) -> some View {
        Button {
            guard !shouldSuppressGridClicks else { return }
            gridFocusID = connection.id
            openConnection(connection)
        } label: {
            connectionCellContent(connection)
        }
        .buttonStyle(.plain)
        .contextMenu { connectionMenu(connection) }
    }

    @ViewBuilder
    private func connectionCellContent(_ connection: Connection) -> some View {
        if let nested = connection.nestedBoard {
            NestedBoardCell(board: nested)
        } else if let block = connection.block {
            switch block.kind {
            case .image, .video:
                MediaBlockCell(block: block)
            case .text:
                TextBlockCell(block: block)
            case .link:
                LinkBlockCell(block: block)
            case .arenaChannel:
                ArenaBlockCell(block: block)
            }
        }
    }

    @ViewBuilder
    private func connectionMenu(_ connection: Connection) -> some View {
        if let block = connection.block, block.kind == .arenaChannel {
            Button("Browse in Colosseum") { openArenaBrowser(for: block) }
            if let urlString = block.arenaURL ?? block.sourceURL,
               let url = URL(string: urlString) {
                Button("Open on Are.na") { NSWorkspace.shared.open(url) }
            }
        }
        if let nested = connection.nestedBoard {
            Button("Open Board") { path.append(nested.id) }
        }
        Divider()
        Button("Remove from Board", role: .destructive) {
            ImportService.removeConnection(connection, deleteOrphanedBlock: true, context: context)
            try? context.save()
        }
    }

    private func adjustColumns(by delta: Int) {
        guard isBrowsingGrid else { return }
        let next = min(
            max(columnCount + delta, ChromeMetrics.boardColumnsMin),
            ChromeMetrics.boardColumnsMax
        )
        guard next != columnCount else { return }
        withAnimation(ColosseumMotion.standard) {
            columnCount = next
        }
    }

    private var columnPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Only drive density while browsing the grid (not block/arena overlays).
                guard isBrowsingGrid, !isAssigningTag else { return }
                if pinchBaseColumns == nil {
                    isPinching = true
                    pinchDidChange = false
                    pinchBaseColumns = columnCount
                    lastPinchStep = 0
                }
                if abs(value - 1) > 0.04 {
                    pinchDidChange = true
                }
                // Pinch out (value > 1) → larger cells → fewer columns.
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
                    // Swallow the mouse-up / click that often follows a trackpad pinch.
                    suppressGridClicksUntil = Date().addingTimeInterval(0.45)
                }
                isPinching = false
                pinchDidChange = false
                pinchBaseColumns = nil
                lastPinchStep = 0
            }
    }

    private func navigateToPathIndex(_ index: Int) {
        if selectedConnectionID != nil {
            withAnimation(ColosseumMotion.overlay) {
                selectedConnectionID = nil
            }
        }
        if arenaBrowseTarget != nil {
            withAnimation(ColosseumMotion.overlay) {
                arenaBrowseTarget = nil
                arenaStack = []
            }
        }
        guard index >= 0, index < path.count else { return }
        withAnimation(ColosseumMotion.overlay) {
            path = Array(path.prefix(index + 1))
        }
    }

    private func jumpArenaStack(to index: Int) {
        guard index >= 0, index < arenaStack.count else { return }
        withAnimation(ColosseumMotion.soft) {
            arenaStack = Array(arenaStack.prefix(index + 1))
        }
    }

    private func handleEscape() {
        // Block preview / Arena browser own Esc (including nested Connect sheets).
        if selectedConnectionID != nil || arenaBrowseTarget != nil { return }
        withAnimation(ColosseumMotion.overlay) {
            if path.count > 1 {
                _ = path.popLast()
            } else {
                path = []
            }
        }
    }

    private func openArenaBrowser(for block: Block) {
        let slug = block.arenaSlug ?? ""
        guard !slug.isEmpty || block.arenaURL != nil || block.sourceURL != nil else { return }
        let target = ArenaBrowseTarget(block: block)
        withAnimation(ColosseumMotion.overlay) {
            arenaStack = [target]
            arenaBrowseTarget = target
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .mpeg4Movie, .quickTimeMovie, .png, .jpeg, .gif, .webP, .heic]
        guard panel.runModal() == .OK else { return }
        Task { await importURLs(panel.urls) }
    }

    private func paste() async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await ImportService.importPasteboard(into: board, context: context)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importURLs(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await ImportService.importFiles(urls, into: board, context: context)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            isImporting = true
            defer { isImporting = false }
            do {
                var fileURLs: [URL] = []
                var strings: [String] = []

                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        if let url = try await loadFileURL(from: provider) {
                            fileURLs.append(url)
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        if let url = try await loadURL(from: provider) {
                            if url.isFileURL {
                                fileURLs.append(url)
                            } else {
                                strings.append(url.absoluteString)
                            }
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        if let text = try await loadString(from: provider) {
                            strings.append(text)
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier),
                              let data = try await loadData(from: provider, type: .gif) {
                        try await importImageData(data, filename: "drop.gif", mimeType: "image/gif")
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier),
                              let data = try await loadData(from: provider, type: .png) {
                        try await importImageData(data, filename: "drop.png", mimeType: "image/png")
                    } else if provider.canLoadObject(ofClass: NSImage.self) {
                        let image = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NSImage, Error>) in
                            _ = provider.loadObject(ofClass: NSImage.self) { object, error in
                                if let error { cont.resume(throwing: error); return }
                                guard let image = object as? NSImage else {
                                    cont.resume(throwing: ImportService.ImportError.failed("Invalid image"))
                                    return
                                }
                                cont.resume(returning: image)
                            }
                        }
                        try await importImage(image)
                    }
                }

                if !fileURLs.isEmpty {
                    try await ImportService.importFiles(fileURLs, into: board, context: context)
                }
                for string in strings {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                        try await ImportService.importURLString(trimmed, into: board, context: context)
                    } else if !trimmed.isEmpty {
                        ImportService.addTextBlock(trimmed, title: "", into: board, context: context)
                    }
                }
                try context.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    private func importImage(_ image: NSImage) async throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { throw ImportService.ImportError.failed("Could not read image") }

        try await importImageData(data, filename: "drop.png", mimeType: "image/png")
    }

    private func importImageData(_ data: Data, filename: String, mimeType: String) async throws {
        let blockID = UUID()
        let dest = try MediaLibrary.writeData(data, into: blockID, filename: filename)
        let (w, h) = ThumbnailService.imageDimensions(at: dest)
        let thumb = try ThumbnailService.generateImageThumbnail(from: dest, blockID: blockID)
        let block = Block(
            id: blockID,
            kind: .image,
            title: "Dropped image",
            localRelativePath: MediaLibrary.relativePath(from: dest),
            thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
            mimeType: mimeType,
            byteSize: Int64(data.count),
            width: w,
            height: h
        )
        context.insert(block)
        ImportService.connect(block: block, to: board, context: context)
    }

    private func loadData(from provider: NSItemProvider, type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: data)
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error { cont.resume(throwing: error); return }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else if let url = item as? URL {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error { cont.resume(throwing: error); return }
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadString(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error { cont.resume(throwing: error); return }
                if let string = item as? String {
                    cont.resume(returning: string)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    cont.resume(returning: string)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
