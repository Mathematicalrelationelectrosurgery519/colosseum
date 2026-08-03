import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Board.updatedAt, order: .reverse) private var boards: [Board]

    @State private var path: [UUID] = []
    @State private var search = ""
    @State private var showNewBoardAlert = false
    @State private var newBoardTitle = ""
    @State private var showImportArena = false
    @State private var arenaBrowseTarget: ArenaBrowseTarget?

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                BoardLibraryView(
                    boards: filteredBoards,
                    search: $search,
                    onOpen: { path.append($0.id) },
                    onCreate: { showNewBoardAlert = true },
                    onImportArena: { showImportArena = true }
                )
                .navigationDestination(for: UUID.self) { boardID in
                    BoardRouteView(boardID: boardID, path: $path)
                }
            }
            .colosseumCanvas()

            if let arenaBrowseTarget {
                ArenaBrowserView(
                    initialTarget: arenaBrowseTarget,
                    destinationBoard: nil,
                    onClose: {
                        withAnimation(ColosseumMotion.overlay) {
                            self.arenaBrowseTarget = nil
                        }
                    },
                    onImportedBoard: { board in
                        path.append(board.id)
                    }
                )
                .transition(ColosseumMotion.overlayTransition)
                .zIndex(30)
            }
        }
        .animation(ColosseumMotion.overlay, value: arenaBrowseTarget?.slug)
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
                    path.append(board.id)
                },
                onBrowse: { target in
                    withAnimation(ColosseumMotion.overlay) {
                        arenaBrowseTarget = target
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumNewBoard)) { _ in
            newBoardTitle = ""
            showNewBoardAlert = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumImportArena)) { _ in
            showImportArena = true
        }
    }

    private var filteredBoards: [Board] {
        guard !search.isEmpty else { return boards }
        return boards.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func createBoard() {
        let title = newBoardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = Board(title: title.isEmpty ? "Untitled" : title)
        context.insert(board)
        try? context.save()
        newBoardTitle = ""
        path.append(board.id)
    }
}
