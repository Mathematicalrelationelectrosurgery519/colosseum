import Foundation

/// Process-wide memoization for expensive board-derived metrics.
enum BoardMetricsCache {
    private struct BoardKey: Hashable {
        let boardID: UUID
        let updatedAt: TimeInterval
        let contentCount: Int
    }

    private static let lock = NSLock()
    private static var storageBytes: [BoardKey: Int64] = [:]
    private static var sortedConnections: [BoardKey: [Connection]] = [:]
    private static let entryLimit = 256

    private static func key(boardID: UUID, updatedAt: Date, contentCount: Int) -> BoardKey {
        BoardKey(
            boardID: boardID,
            updatedAt: updatedAt.timeIntervalSinceReferenceDate,
            contentCount: contentCount
        )
    }

    static func storageBytes(
        boardID: UUID,
        updatedAt: Date,
        contentCount: Int,
        compute: () -> Int64
    ) -> Int64 {
        let key = key(boardID: boardID, updatedAt: updatedAt, contentCount: contentCount)
        lock.lock()
        if let cached = storageBytes[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let value = compute()

        lock.lock()
        if storageBytes.count >= entryLimit {
            storageBytes.removeAll(keepingCapacity: true)
        }
        storageBytes[key] = value
        lock.unlock()
        return value
    }

    static func sortedConnections(
        boardID: UUID,
        updatedAt: Date,
        contentCount: Int,
        compute: () -> [Connection]
    ) -> [Connection] {
        let key = key(boardID: boardID, updatedAt: updatedAt, contentCount: contentCount)
        lock.lock()
        if let cached = sortedConnections[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let value = compute()

        lock.lock()
        if sortedConnections.count >= entryLimit {
            sortedConnections.removeAll(keepingCapacity: true)
        }
        sortedConnections[key] = value
        lock.unlock()
        return value
    }
}

/// Cheap identity for large grid lists — avoids allocating full id arrays for animation/onChange.
struct GridListIdentity<ID: Hashable>: Equatable {
    var count: Int
    var firstID: ID?
    var lastID: ID?
    /// Extra revision (e.g. `updatedAt` bit-pattern or item total) so middle mutations still invalidate.
    var revision: UInt64

    init(count: Int, firstID: ID?, lastID: ID?, revision: UInt64 = 0) {
        self.count = count
        self.firstID = firstID
        self.lastID = lastID
        self.revision = revision
    }

    /// Keep `focus` if it still appears in `ids`; otherwise return the first id (or nil).
    static func revalidatedFocus(_ focus: ID?, in ids: some Sequence<ID>) -> ID? {
        var first: ID?
        for id in ids {
            if first == nil { first = id }
            if let focus, id == focus { return focus }
        }
        return first
    }
}

enum GridListIdentities {
    static func connections(
        _ items: [Connection],
        revision: UInt64 = 0
    ) -> GridListIdentity<UUID> {
        GridListIdentity(
            count: items.count,
            firstID: items.first?.id,
            lastID: items.last?.id,
            revision: revision
        )
    }

    static func boards(
        _ items: [Board],
        revision: UInt64 = 0
    ) -> GridListIdentity<UUID> {
        GridListIdentity(
            count: items.count,
            firstID: items.first?.id,
            lastID: items.last?.id,
            revision: revision
        )
    }

    static func arenaItems(
        _ items: [ArenaContentItem],
        revision: UInt64 = 0
    ) -> GridListIdentity<Int> {
        GridListIdentity(
            count: items.count,
            firstID: items.first?.id,
            lastID: items.last?.id,
            revision: revision
        )
    }
}
