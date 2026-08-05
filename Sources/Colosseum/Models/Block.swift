import Foundation
import SwiftData

@Model
final class Block {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var notes: String
    var createdAt: Date
    var sourceURL: String?
    var localRelativePath: String?
    var thumbRelativePath: String?
    var mimeType: String?
    var byteSize: Int64
    var width: Int
    var height: Int
    var duration: Double
    var textBody: String

    // Are.na channel preview fields
    var arenaSlug: String?
    var arenaURL: String?
    var arenaOwnerName: String?
    var arenaOwnerSlug: String?
    var arenaBlockCount: Int
    var arenaUpdatedAt: Date?
    var arenaBlockID: Int?
    var arenaTypeName: String?
    var remoteMediaURL: String?
    var remoteThumbnailURL: String?

    @Relationship(deleteRule: .cascade, inverse: \Connection.block)
    var connections: [Connection] = []

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .link }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: BlockKind,
        title: String,
        notes: String = "",
        sourceURL: String? = nil,
        localRelativePath: String? = nil,
        thumbRelativePath: String? = nil,
        mimeType: String? = nil,
        byteSize: Int64 = 0,
        width: Int = 0,
        height: Int = 0,
        duration: Double = 0,
        textBody: String = "",
        arenaSlug: String? = nil,
        arenaURL: String? = nil,
        arenaOwnerName: String? = nil,
        arenaOwnerSlug: String? = nil,
        arenaBlockCount: Int = 0,
        arenaUpdatedAt: Date? = nil,
        arenaBlockID: Int? = nil,
        arenaTypeName: String? = nil,
        remoteMediaURL: String? = nil,
        remoteThumbnailURL: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.notes = notes
        self.createdAt = .now
        self.sourceURL = sourceURL
        self.localRelativePath = localRelativePath
        self.thumbRelativePath = thumbRelativePath
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.duration = duration
        self.textBody = textBody
        self.arenaSlug = arenaSlug
        self.arenaURL = arenaURL
        self.arenaOwnerName = arenaOwnerName
        self.arenaOwnerSlug = arenaOwnerSlug
        self.arenaBlockCount = arenaBlockCount
        self.arenaUpdatedAt = arenaUpdatedAt
        self.arenaBlockID = arenaBlockID
        self.arenaTypeName = arenaTypeName
        self.remoteMediaURL = remoteMediaURL
        self.remoteThumbnailURL = remoteThumbnailURL
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if kind == .text {
            let first = textBody.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            return first.isEmpty ? "Untitled text" : first
        }
        return "Untitled"
    }

    var contentTypeLabel: String {
        switch kind {
        case .image: return mimeType ?? "image"
        case .video: return mimeType ?? "video"
        case .link: return "link"
        case .text: return "text"
        case .arenaChannel: return "are.na channel"
        }
    }

    /// GIFs (and other multi-frame images) should play via `AnimatedImageView`.
    var isAnimatedImage: Bool {
        guard kind == .image else { return false }
        if AnimatedImage.isGIF(mimeType: mimeType) { return true }
        if let path = localRelativePath {
            let ext = URL(fileURLWithPath: path).pathExtension
            if AnimatedImage.isGIF(pathExtension: ext) { return true }
        }
        return false
    }

    var isRemoteMediaReference: Bool {
        localRelativePath == nil && remoteMediaURL != nil && (kind == .image || kind == .video)
    }
}
