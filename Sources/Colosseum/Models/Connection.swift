import Foundation
import SwiftData

@Model
final class Connection {
    @Attribute(.unique) var id: UUID
    var position: Int
    var createdAt: Date

    var board: Board?
    var block: Block?
    var nestedBoard: Board?

    init(board: Board, block: Block? = nil, nestedBoard: Board? = nil, position: Int) {
        self.id = UUID()
        self.position = position
        self.createdAt = .now
        self.board = board
        self.block = block
        self.nestedBoard = nestedBoard
    }
}
