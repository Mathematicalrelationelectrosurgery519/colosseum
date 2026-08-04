import Foundation
import SwiftData

@Model
final class Board {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Connection.board)
    var connections: [Connection] = []

    @Relationship(deleteRule: .nullify, inverse: \Connection.nestedBoard)
    var nestedIn: [Connection] = []

    init(title: String, notes: String = "") {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }

    var sortedConnections: [Connection] {
        BoardMetricsCache.sortedConnections(
            boardID: id,
            updatedAt: updatedAt,
            contentCount: connections.count
        ) {
            connections.sorted { $0.position < $1.position }
        }
    }

    var contentCount: Int {
        connections.count
    }

    /// Sum of local media bytes for blocks on this board (includes nested boards, cycle-safe).
    var storageBytes: Int64 {
        BoardMetricsCache.storageBytes(
            boardID: id,
            updatedAt: updatedAt,
            contentCount: connections.count
        ) {
            Self.computeStorageBytes(board: self, visited: [])
        }
    }

    private static func computeStorageBytes(board: Board, visited: Set<UUID>) -> Int64 {
        guard !visited.contains(board.id) else { return 0 }
        var seen = visited
        seen.insert(board.id)
        return board.connections.reduce(into: Int64(0)) { total, connection in
            if let block = connection.block {
                total += max(block.byteSize, 0)
            } else if let nested = connection.nestedBoard {
                total += computeStorageBytes(board: nested, visited: seen)
            }
        }
    }
}
