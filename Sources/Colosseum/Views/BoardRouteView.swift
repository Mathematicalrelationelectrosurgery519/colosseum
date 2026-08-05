import SwiftData
import SwiftUI

struct BoardRouteView: View {
    let boardID: UUID
    @Binding var path: [UUID]
    let initialConnectionID: UUID?
    var onInitialConnectionConsumed: () -> Void
    @Query private var boards: [Board]

    init(
        boardID: UUID,
        path: Binding<[UUID]>,
        initialConnectionID: UUID? = nil,
        onInitialConnectionConsumed: @escaping () -> Void = {}
    ) {
        self.boardID = boardID
        self._path = path
        self.initialConnectionID = initialConnectionID
        self.onInitialConnectionConsumed = onInitialConnectionConsumed
        let id = boardID
        _boards = Query(filter: #Predicate<Board> { $0.id == id })
    }

    var body: some View {
        if let board = boards.first {
            BoardOverviewView(
                board: board,
                path: $path,
                initialConnectionID: initialConnectionID,
                onInitialConnectionConsumed: onInitialConnectionConsumed
            )
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
