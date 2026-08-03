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
        connections.sorted { $0.position < $1.position }
    }

    var contentCount: Int {
        connections.count
    }
}
