import SwiftData
import SwiftUI

struct BoardLibraryView: View {
    let boards: [Board]
    var showsToolbar = true
    var onOpen: (Board) -> Void
    var onCreate: () -> Void
    var onImportArena: () -> Void

    @State private var gridFocusID: UUID?
    @State private var gridWidth: CGFloat = 900
    @State private var keyMonitor = KeyNavMonitor()
    @FocusState private var homeFocused: Bool
    @State private var showSearch = false
    @State private var searchQuery = ""

    private let minCardWidth: CGFloat = 200

    private var columnCount: Int {
        let inner = max(minCardWidth, gridWidth - 56)
        return max(1, Int((inner + ColosseumTheme.gridGap) / (minCardWidth + ColosseumTheme.gridGap)))
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minCardWidth, maximum: 280), spacing: ColosseumTheme.gridGap)]
    }

    private var filteredBoards: [Board] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard showSearch, !query.isEmpty else { return boards }
        return boards.filter {
            BoardContentSearch.matches([$0.title], query: query)
        }
    }

    private var filteredListIdentity: GridListIdentity<UUID> {
        var hasher = Hasher()
        hasher.combine(boards.count)
        hasher.combine(showSearch)
        hasher.combine(searchQuery)
        if let first = boards.first { hasher.combine(first.updatedAt.timeIntervalSinceReferenceDate) }
        if let last = boards.last { hasher.combine(last.updatedAt.timeIntervalSinceReferenceDate) }
        return GridListIdentities.boards(
            filteredBoards,
            revision: UInt64(bitPattern: Int64(hasher.finalize()))
        )
    }

    /// Grid nav active (not while the search field owns typing).
    private var isBrowsingGrid: Bool { showsToolbar && !showSearch }
    /// Keep the key monitor alive during search so Esc still dismisses.
    private var ownsKeyboard: Bool { showsToolbar }

    var body: some View {
        libraryContent
            .background(ColosseumTheme.canvas)
            .navigationTitle("")
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(ColosseumTheme.canvas, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarColorScheme(.dark, for: .windowToolbar)
            .toolbar { libraryToolbar }
            .focusable()
            .focused($homeFocused)
            .focusEffectDisabled()
            .onAppear { syncHomeKeyboard() }
            .onDisappear { keyMonitor.remove() }
            .onChange(of: showsToolbar) { _, active in
                if !active { dismissSearch() }
                syncHomeKeyboard()
            }
            .onChange(of: ownsKeyboard) { _, owns in
                if owns {
                    syncHomeKeyboard()
                } else {
                    keyMonitor.remove()
                }
            }
            .onChange(of: showSearch) { _, searching in
                if !searching, ownsKeyboard {
                    syncHomeKeyboard()
                }
            }
            .onChange(of: filteredListIdentity) { _, _ in
                gridFocusID = GridListIdentity.revalidatedFocus(
                    gridFocusID,
                    in: filteredBoards.lazy.map(\.id)
                )
            }
            .onExitCommand {
                if showSearch {
                    withAnimation(ColosseumMotion.overlay) {
                        dismissSearch()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .colosseumSearch)) { _ in
                guard showsToolbar else { return }
                toggleSearch()
            }
            .animation(ColosseumMotion.overlay, value: showSearch)
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        if showsToolbar {
                ColosseumCenterHeaderToolbar(
                    isSearching: showSearch,
                    searchQuery: $searchQuery,
                    placeholder: "Search boards…",
                    visible: true,
                    onDismissSearch: {
                        withAnimation(ColosseumMotion.overlay) {
                            dismissSearch()
                        }
                    }
                ) {
                    Color.clear
                        .frame(
                            width: ChromeMetrics.headerCenterWidth,
                            height: ChromeMetrics.controlHeight
                        )
                }
            }
        }

    private var libraryContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                libraryScrollBody
            }
            .onPreferenceChange(HomeGridWidthKey.self) { gridWidth = $0 }
            .onChange(of: gridFocusID) { _, id in
                guard let id, isBrowsingGrid else { return }
                withAnimation(ColosseumMotion.soft) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var libraryScrollBody: some View {
        if boards.isEmpty {
            emptyState
        } else if filteredBoards.isEmpty {
            Text(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Type to filter boards"
                : "No boards match")
                .font(.system(size: 13))
                .foregroundStyle(ColosseumTheme.tertiaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else {
            boardGrid
        }
    }

    private var boardGrid: some View {
        LazyVGrid(columns: columns, spacing: ColosseumTheme.gridGap) {
            ForEach(filteredBoards, id: \.id) { board in
                boardCell(board)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 40)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: HomeGridWidthKey.self, value: geo.size.width)
            }
        )
        .animation(ColosseumMotion.soft, value: filteredListIdentity)
    }

    private func boardCell(_ board: Board) -> some View {
        let focused = board.id == gridFocusID && isBrowsingGrid
        return Button {
            gridFocusID = board.id
            onOpen(board)
        } label: {
            BoardCardView(
                board: board,
                searchQuery: showSearch ? searchQuery : ""
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .id(board.id)
        .overlay {
            if focused {
                focusRing
            }
        }
    }

    private var focusRing: some View {
        let gap = ColosseumTheme.selectionRingGap
        let lineWidth = ColosseumTheme.selectionRingWidth
        let outset = gap + lineWidth / 2
        return Rectangle()
            .stroke(Color.white.opacity(0.85), lineWidth: lineWidth)
            .padding(.bottom, 22 - outset)
            .padding(.top, -outset)
            .padding(.horizontal, -outset)
            .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No boards yet")
                .font(.title3)
                .foregroundStyle(ColosseumTheme.primaryText)
            Text("Create a board with ⌘↩, or import with ⌘I.")
                .font(.callout)
                .foregroundStyle(ColosseumTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    private func toggleSearch() {
        withAnimation(ColosseumMotion.overlay) {
            if showSearch {
                dismissSearch()
            } else {
                searchQuery = ""
                showSearch = true
            }
        }
    }

    private func dismissSearch() {
        showSearch = false
        searchQuery = ""
        syncHomeKeyboard()
    }

    private func syncHomeKeyboard() {
        guard ownsKeyboard else {
            keyMonitor.remove()
            return
        }
        homeFocused = true
        keyMonitor.onLeft = { moveFocus(delta: -1) }
        keyMonitor.onRight = { moveFocus(delta: 1) }
        keyMonitor.onUp = { moveFocus(delta: -columnCount) }
        keyMonitor.onDown = { moveFocus(delta: columnCount) }
        keyMonitor.onEnter = { openFocused() }
        keyMonitor.onEscape = {
            if showSearch {
                withAnimation(ColosseumMotion.overlay) {
                    dismissSearch()
                }
            }
        }
        // While searching, ignore arrows/enter but still route Esc (incl. from the text field).
        keyMonitor.shouldIgnoreNavigation = { !isBrowsingGrid }
        keyMonitor.install()
        DispatchQueue.main.async {
            homeFocused = true
            if gridFocusID == nil {
                gridFocusID = filteredBoards.first?.id
            }
        }
    }

    private func moveFocus(delta: Int) {
        guard isBrowsingGrid, !filteredBoards.isEmpty else { return }
        homeFocused = true
        if let idx = filteredBoards.firstIndex(where: { $0.id == gridFocusID }) {
            let next = idx + delta
            guard next >= 0, next < filteredBoards.count else { return }
            withAnimation(ColosseumMotion.soft) {
                gridFocusID = filteredBoards[next].id
            }
        } else {
            withAnimation(ColosseumMotion.soft) {
                gridFocusID = filteredBoards[0].id
            }
        }
    }

    private func openFocused() {
        guard isBrowsingGrid else { return }
        let board = filteredBoards.first(where: { $0.id == gridFocusID }) ?? filteredBoards.first
        guard let board else { return }
        gridFocusID = board.id
        onOpen(board)
    }
}

private struct HomeGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BoardCardView: View {
    let board: Board
    var searchQuery: String = ""

    private var caption: (text: String, highlight: String) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return (board.title, "") }
        if board.title.localizedCaseInsensitiveContains(query) {
            return (BoardContentSearch.matchSnippet(in: board.title, query: query), query)
        }
        return (board.title, "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Rectangle()
                    .fill(ColosseumTheme.surface)
                VStack(spacing: 6) {
                    Text(board.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ColosseumTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text("\(board.contentCount) blocks")
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.secondaryText)
                    Text(ColosseumFormatters.relativeDate(board.updatedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                    Text(ColosseumFormatters.byteCount(board.storageBytes))
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                }
                .padding(16)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

            NotesPreviewLine(text: caption.text, highlightQuery: caption.highlight)
                .frame(height: 16)
        }
    }
}
