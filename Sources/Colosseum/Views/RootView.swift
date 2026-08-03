import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Board.updatedAt, order: .reverse) private var boards: [Board]

    @State private var path: [UUID] = []
    @State private var showNewBoardAlert = false
    @State private var newBoardTitle = ""
    @State private var showImportArena = false
    @State private var showSearch = false
    @State private var arenaBrowseTarget: ArenaBrowseTarget?
    @State private var arenaStack: [ArenaBrowseTarget] = []
    @AppStorage("boardColumnCount") private var columnCount = ChromeMetrics.boardColumnsDefault

    var body: some View {
        ZStack {
            // NavigationStack hosts the window toolbar; path is owned separately for fade transitions.
            NavigationStack {
                ZStack {
                    BoardLibraryView(
                        boards: boards,
                        showsToolbar: path.isEmpty,
                        onOpen: { openBoard($0.id) },
                        onCreate: { showNewBoardAlert = true },
                        onImportArena: { showImportArena = true },
                        onSearch: {
                            withAnimation(ColosseumMotion.overlay) {
                                showSearch = true
                            }
                        }
                    )
                    .opacity(path.isEmpty ? 1 : 0)
                    .allowsHitTesting(path.isEmpty)

                    if let boardID = path.last {
                        BoardRouteView(boardID: boardID, path: $path)
                            .id(boardID)
                            .transition(ColosseumMotion.overlayTransition)
                            .zIndex(1)
                    }
                }
                .animation(ColosseumMotion.overlay, value: path)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .colosseumCanvas()
                .toolbarBackground(ColosseumTheme.canvas, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarColorScheme(.dark, for: .windowToolbar)
                // Stable leading slot — same item on home and board so the mark never shifts.
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        AppHomeButton {
                            guard !path.isEmpty else { return }
                            withAnimation(ColosseumMotion.overlay) {
                                path = []
                            }
                        }
                        .frame(height: ChromeMetrics.controlHeight)
                    }
                    .colosseumPlainToolbarItem()
                }
            }
            .modifier(WindowContainerBackground())

            if let arenaBrowseTarget {
                ArenaBrowserView(
                    initialTarget: arenaBrowseTarget,
                    stack: $arenaStack,
                    destinationBoard: nil,
                    showsInlineChrome: true,
                    onClose: {
                        withAnimation(ColosseumMotion.overlay) {
                            self.arenaBrowseTarget = nil
                            arenaStack = []
                        }
                    },
                    onImportedBoard: { board in
                        withAnimation(ColosseumMotion.overlay) {
                            self.arenaBrowseTarget = nil
                            arenaStack = []
                        }
                        openBoard(board.id)
                    }
                )
                .transition(ColosseumMotion.overlayTransition)
                .zIndex(30)
            }

            if showSearch {
                BoardSearchView(
                    boards: boards,
                    onSelect: { board in
                        withAnimation(ColosseumMotion.overlay) {
                            showSearch = false
                            path = [board.id]
                        }
                    },
                    onClose: {
                        withAnimation(ColosseumMotion.overlay) {
                            showSearch = false
                        }
                    }
                )
                .zIndex(40)
            }
        }
        .animation(ColosseumMotion.overlay, value: arenaBrowseTarget?.slug)
        .animation(ColosseumMotion.overlay, value: showSearch)
        .alert("New Board", isPresented: $showNewBoardAlert) {
            TextField("Title", text: $newBoardTitle)
            Button("Create") { createBoard() }
            Button("Cancel", role: .cancel) { newBoardTitle = "" }
        } message: {
            Text("Name your board. You can rename it later.")
        }
        .sheet(isPresented: $showImportArena) {
            ImportArenaSheet(
                onImported: { board in
                    openBoard(board.id)
                },
                onBrowse: { target in
                    withAnimation(ColosseumMotion.overlay) {
                        arenaStack = [target]
                        arenaBrowseTarget = target
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumNewBoard)) { _ in
            newBoardTitle = ""
            showNewBoardAlert = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumCommandReturn)) { _ in
            if path.isEmpty {
                newBoardTitle = ""
                showNewBoardAlert = true
            } else {
                NotificationCenter.default.post(name: .colosseumAdd, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumImportArena)) { _ in
            showImportArena = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumSearch)) { _ in
            withAnimation(ColosseumMotion.overlay) {
                showSearch.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumGoHome)) { _ in
            withAnimation(ColosseumMotion.overlay) { path = [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumColumnsIncrease)) { _ in
            guard path.isEmpty else { return }
            columnCount = min(columnCount + 1, ChromeMetrics.boardColumnsMax)
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumColumnsDecrease)) { _ in
            guard path.isEmpty else { return }
            columnCount = max(columnCount - 1, ChromeMetrics.boardColumnsMin)
        }
    }

    private func openBoard(_ id: UUID) {
        withAnimation(ColosseumMotion.overlay) {
            path = [id]
        }
    }

    private func createBoard() {
        let title = newBoardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = Board(title: title.isEmpty ? "Untitled" : title)
        context.insert(board)
        try? context.save()
        newBoardTitle = ""
        openBoard(board.id)
    }
}
