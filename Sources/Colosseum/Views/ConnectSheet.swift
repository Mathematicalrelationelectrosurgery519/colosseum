import SwiftData
import SwiftUI

struct ConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Board.title) private var boards: [Board]

    let block: Block?
    let nestedBoard: Board?
    let excludeBoardID: UUID?

    @State private var search = ""

    private var filtered: [Board] {
        boards.filter { board in
            if let excludeBoardID, board.id == excludeBoardID { return false }
            if let nestedBoard, board.id == nestedBoard.id { return false }
            if let block, board.connections.contains(where: { $0.block?.id == block.id }) { return false }
            if let nestedBoard, board.connections.contains(where: { $0.nestedBoard?.id == nestedBoard.id }) {
                return false
            }
            if search.isEmpty { return true }
            return board.title.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connect →")
                    .font(.headline)
                    .foregroundStyle(ColosseumTheme.primaryText)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            TextField("Filter boards", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider().overlay(ColosseumTheme.border)

            if filtered.isEmpty {
                Text("No boards available")
                    .foregroundStyle(ColosseumTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, id: \.id) { board in
                    Button {
                        connect(to: board)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(board.title)
                                    .foregroundStyle(ColosseumTheme.primaryText)
                                Text("\(board.contentCount) blocks")
                                    .font(.caption)
                                    .foregroundStyle(ColosseumTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundStyle(ColosseumTheme.tertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(ColosseumTheme.canvas)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 420, height: 480)
        .background(ColosseumTheme.canvas)
    }

    private func connect(to board: Board) {
        if let block {
            ImportService.connect(block: block, to: board, context: context)
        } else if let nestedBoard {
            ImportService.connect(nestedBoard: nestedBoard, to: board, context: context)
        }
        try? context.save()
        dismiss()
    }
}
