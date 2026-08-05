import Foundation

enum BlockKind: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case audio
    case link
    case text
    case arenaChannel
}
