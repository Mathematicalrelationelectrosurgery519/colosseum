import SwiftData
import SwiftUI

struct BoardRouteView: View {
    let boardID: UUID
    @Binding var path: [UUID]
    @Query private var boards: [Board]

    init(boardID: UUID, path: Binding<[UUID]>) {
        self.boardID = boardID
        self._path = path
        let id = boardID
        _boards = Query(filter: #Predicate<Board> { $0.id == id })
    }

    var body: some View {
        if let board = boards.first {
            BoardOverviewView(board: board, path: $path)
        } else {
            ContentUnavailableView(
                "Board not found",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("This board may have been deleted.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ColosseumTheme.canvas)
        }
    }
}
