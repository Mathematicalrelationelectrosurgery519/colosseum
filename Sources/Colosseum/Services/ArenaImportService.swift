import Foundation
import SwiftData

@MainActor
enum ArenaImportService {
    struct Progress: Sendable {
        var phase: String
        var completed: Int
        var total: Int
    }

    /// Creates a new local board and imports public Are.na channel contents (one-way).
    @discardableResult
    static func importChannel(
        fromURLString urlString: String,
        context: ModelContext,
        progress: (@MainActor (Progress) -> Void)? = nil
    ) async throws -> Board {
        progress?(Progress(phase: "Fetching channel…", completed: 0, total: 0))

        let preview = try await ArenaService.fetchFromURLString(urlString)
        progress?(Progress(phase: "Loading contents…", completed: 0, total: preview.blockCount))

        let items = try await ArenaService.fetchAllContents(slug: preview.slug)
        let board = Board(
            title: preview.title,
            notes: preview.notes.isEmpty
                ? "Imported from Are.na · \(preview.url.absoluteString)"
                : preview.notes
        )
        context.insert(board)

        let total = items.count
        var completed = 0

        for item in items {
            progress?(Progress(
                phase: "Importing \(completed + 1) of \(total)…",
                completed: completed,
                total: total
            ))
            do {
                try await importItem(item, into: board, channelURL: preview.url, context: context)
            } catch {
                // Skip individual failures; keep going so one bad file doesn't abort the board.
                print("Colosseum: skipped Are.na item \(item.id) (\(item.typeName)): \(error)")
            }
            completed += 1
            if completed % 5 == 0 {
                try context.save()
            }
        }

        board.updatedAt = .now
        try context.save()
        progress?(Progress(phase: "Done", completed: total, total: total))
        return board
    }

    /// Connects a single remote Are.na item as a reference without downloading its media.
    static func saveItem(
        _ item: ArenaContentItem,
        into board: Board,
        context: ModelContext
    ) async throws {
        let block = existingBlock(for: item, context: context) ?? makeRemoteReference(for: item)
        if block.modelContext == nil {
            context.insert(block)
        }
        ImportService.connect(block: block, to: board, context: context)
        board.updatedAt = .now
        try context.save()
    }

    private static func existingBlock(for item: ArenaContentItem, context: ModelContext) -> Block? {
        let blocks = (try? context.fetch(FetchDescriptor<Block>())) ?? []
        if item.kind == .channel, let slug = item.channelSlug {
            return blocks.first { $0.kind == .arenaChannel && $0.arenaSlug == slug }
        }
        return blocks.first { $0.arenaBlockID == item.id }
    }

    private static func makeRemoteReference(for item: ArenaContentItem) -> Block {
        let kind: BlockKind
        switch item.kind {
        case .image:
            kind = .image
        case .attachment:
            if item.isVideo {
                kind = .video
            } else if item.isAudio {
                kind = .audio
            } else if item.attachmentMime?.lowercased().hasPrefix("image/") == true || item.imageURL != nil {
                kind = .image
            } else {
                kind = .link
            }
        case .link, .other:
            kind = .link
        case .text:
            kind = .text
        case .channel:
            kind = .arenaChannel
        }

        let mediaURL: String?
        if kind == .video || kind == .audio {
            mediaURL = item.attachmentURL
        } else if kind == .image {
            mediaURL = item.imageURL ?? item.attachmentURL
        } else {
            mediaURL = nil
        }
        let sourceURL = item.sourceURL
            ?? (kind == .link ? item.attachmentURL : nil)
            ?? mediaURL
            ?? item.previewURL
        let bytes = kind == .video || kind == .audio
            ? item.attachmentBytes
            : max(item.imageBytes, item.attachmentBytes)
        let arenaURL = item.kind == .channel
            ? item.previewURL
            : "https://www.are.na/block/\(item.id)"

        return Block(
            kind: kind,
            title: item.title.isEmpty ? item.displayTitle : item.title,
            notes: item.notes,
            sourceURL: sourceURL,
            mimeType: kind == .video || kind == .audio
                ? item.attachmentMime
                : item.imageMime ?? item.attachmentMime,
            byteSize: bytes,
            width: item.imageWidth,
            height: item.imageHeight,
            textBody: item.textBody,
            arenaSlug: item.channelSlug,
            arenaURL: arenaURL,
            arenaOwnerName: item.channelOwnerName,
            arenaOwnerSlug: item.channelOwnerSlug,
            arenaBlockCount: item.channelBlockCount,
            arenaUpdatedAt: item.channelUpdatedAt,
            arenaBlockID: item.kind == .channel ? nil : item.id,
            arenaTypeName: item.typeName,
            remoteMediaURL: mediaURL,
            remoteThumbnailURL: item.gridImageURL
        )
    }

    private static func importItem(
        _ item: ArenaContentItem,
        into board: Board,
        channelURL: URL,
        context: ModelContext
    ) async throws {
        switch item.kind {
        case .image:
            try await importImage(item, into: board, context: context)

        case .attachment:
            if let mime = item.attachmentMime?.lowercased(), mime.hasPrefix("video/"),
               let url = item.attachmentURL {
                try await importVideo(from: url, item: item, into: board, context: context)
            } else if let mime = item.attachmentMime?.lowercased(), mime.hasPrefix("audio/"),
                      let url = item.attachmentURL {
                try await importAudio(from: url, item: item, into: board, context: context)
            } else if let mime = item.attachmentMime?.lowercased(), mime.hasPrefix("image/"),
                      let url = item.attachmentURL {
                try await importRemoteImage(urlString: url, item: item, into: board, context: context)
            } else if let url = item.attachmentURL {
                // Non-media attachment → link block
                let block = Block(
                    kind: .link,
                    title: item.title.isEmpty ? (item.attachmentFilename ?? "Attachment") : item.title,
                    notes: item.notes,
                    sourceURL: url,
                    mimeType: item.attachmentMime
                )
                applyArenaMetadata(item, to: block)
                context.insert(block)
                ImportService.connect(block: block, to: board, context: context)
            } else if item.imageURL != nil {
                try await importImage(item, into: board, context: context)
            }

        case .link:
            let blockID = UUID()
            var thumbPath: String?
            var localPath: String?
            var width = 0
            var height = 0
            if let imageURL = item.imageURL,
               let data = try? await ArenaService.download(imageURL) {
                let name = item.imageFilename ?? "preview.jpg"
                let dest = try MediaLibrary.writeData(data, into: blockID, filename: name)
                localPath = MediaLibrary.relativePath(from: dest)
                width = item.imageWidth
                height = item.imageHeight
                if let thumb = try? ThumbnailService.generateImageThumbnail(from: dest, blockID: blockID) {
                    thumbPath = MediaLibrary.relativePath(from: thumb)
                }
            }
            let block = Block(
                id: blockID,
                kind: .link,
                title: item.title.isEmpty ? (item.sourceURL ?? "Link") : item.title,
                notes: item.notes,
                sourceURL: item.sourceURL,
                localRelativePath: localPath,
                thumbRelativePath: thumbPath,
                mimeType: "text/html",
                width: width,
                height: height
            )
            applyArenaMetadata(item, to: block)
            context.insert(block)
            ImportService.connect(block: block, to: board, context: context)

        case .text:
            let body = item.textBody.isEmpty ? item.notes : item.textBody
            guard !body.isEmpty || !item.title.isEmpty else { return }
            let block = Block(
                kind: .text,
                title: item.title,
                notes: item.notes,
                textBody: body
            )
            applyArenaMetadata(item, to: block)
            context.insert(block)
            ImportService.connect(block: block, to: board, context: context)

        case .channel:
            guard let slug = item.channelSlug else { return }
            let ownerSlug = item.channelOwnerSlug ?? "are.na"
            let pageURL = URL(string: "https://www.are.na/\(ownerSlug)/\(slug)")!
            let block = Block(
                kind: .arenaChannel,
                title: item.title.isEmpty ? slug : item.title,
                notes: item.notes,
                sourceURL: pageURL.absoluteString,
                arenaSlug: slug,
                arenaURL: pageURL.absoluteString,
                arenaOwnerName: item.channelOwnerName,
                arenaBlockCount: item.channelBlockCount,
                arenaUpdatedAt: item.channelUpdatedAt
            )
            applyArenaMetadata(item, to: block)
            context.insert(block)
            ImportService.connect(block: block, to: board, context: context)

        case .other:
            if let source = item.sourceURL {
                let block = Block(
                    kind: .link,
                    title: item.title.isEmpty ? source : item.title,
                    notes: item.notes,
                    sourceURL: source
                )
                applyArenaMetadata(item, to: block)
                context.insert(block)
                ImportService.connect(block: block, to: board, context: context)
            } else if item.imageURL != nil {
                try await importImage(item, into: board, context: context)
            }
        }
    }

    private static func importImage(
        _ item: ArenaContentItem,
        into board: Board,
        context: ModelContext
    ) async throws {
        guard let url = item.imageURL else { return }
        try await importRemoteImage(urlString: url, item: item, into: board, context: context)
    }

    private static func importRemoteImage(
        urlString: String,
        item: ArenaContentItem,
        into board: Board,
        context: ModelContext
    ) async throws {
        let data = try await ArenaService.download(urlString)
        let blockID = UUID()
        let filename = item.imageFilename
            ?? item.attachmentFilename
            ?? URL(string: urlString)?.lastPathComponent
            ?? "image.jpg"
        let dest = try MediaLibrary.writeData(data, into: blockID, filename: filename)
        let (w, h) = ThumbnailService.imageDimensions(at: dest)
        let thumb = try ThumbnailService.generateImageThumbnail(from: dest, blockID: blockID)
        let block = Block(
            id: blockID,
            kind: .image,
            title: item.title.isEmpty ? filename : item.title,
            notes: item.notes,
            sourceURL: item.sourceURL ?? urlString,
            localRelativePath: MediaLibrary.relativePath(from: dest),
            thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
            mimeType: item.imageMime ?? item.attachmentMime ?? "image/jpeg",
            byteSize: Int64(data.count),
            width: w > 0 ? w : item.imageWidth,
            height: h > 0 ? h : item.imageHeight
        )
        applyArenaMetadata(item, to: block)
        context.insert(block)
        ImportService.connect(block: block, to: board, context: context)
    }

    private static func importVideo(
        from urlString: String,
        item: ArenaContentItem,
        into board: Board,
        context: ModelContext
    ) async throws {
        let data = try await ArenaService.download(urlString)
        let blockID = UUID()
        let filename = item.attachmentFilename
            ?? URL(string: urlString)?.lastPathComponent
            ?? "video.mp4"
        let dest = try MediaLibrary.writeData(data, into: blockID, filename: filename)
        let meta = await ThumbnailService.videoMetadata(at: dest)
        let thumb = try? await ThumbnailService.generateVideoThumbnail(from: dest, blockID: blockID)
        let block = Block(
            id: blockID,
            kind: .video,
            title: item.title.isEmpty ? filename : item.title,
            notes: item.notes,
            sourceURL: urlString,
            localRelativePath: MediaLibrary.relativePath(from: dest),
            thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
            mimeType: item.attachmentMime ?? "video/mp4",
            byteSize: Int64(data.count),
            width: meta.width,
            height: meta.height,
            duration: meta.duration
        )
        applyArenaMetadata(item, to: block)
        context.insert(block)
        ImportService.connect(block: block, to: board, context: context)
    }

    private static func importAudio(
        from urlString: String,
        item: ArenaContentItem,
        into board: Board,
        context: ModelContext
    ) async throws {
        let data = try await ArenaService.download(urlString)
        let blockID = UUID()
        let filename = item.attachmentFilename
            ?? URL(string: urlString)?.lastPathComponent
            ?? "audio.mp3"
        let dest = try MediaLibrary.writeData(data, into: blockID, filename: filename)
        let meta = await ThumbnailService.videoMetadata(at: dest)
        let block = Block(
            id: blockID,
            kind: .audio,
            title: item.title.isEmpty ? filename : item.title,
            notes: item.notes,
            sourceURL: urlString,
            localRelativePath: MediaLibrary.relativePath(from: dest),
            mimeType: item.attachmentMime ?? "audio/mpeg",
            byteSize: Int64(data.count),
            duration: meta.duration
        )
        applyArenaMetadata(item, to: block)
        context.insert(block)
        ImportService.connect(block: block, to: board, context: context)
    }

    private static func applyArenaMetadata(_ item: ArenaContentItem, to block: Block) {
        block.arenaBlockID = item.kind == .channel ? nil : item.id
        block.arenaTypeName = item.typeName
        block.arenaOwnerName = item.channelOwnerName
        block.arenaOwnerSlug = item.channelOwnerSlug
        block.arenaUpdatedAt = item.channelUpdatedAt
        block.remoteMediaURL = item.isVideo || item.isAudio
            ? item.attachmentURL
            : item.imageURL ?? item.attachmentURL
        block.remoteThumbnailURL = item.gridImageURL
        if item.kind != .channel {
            block.arenaURL = "https://www.are.na/block/\(item.id)"
        }
    }
}
