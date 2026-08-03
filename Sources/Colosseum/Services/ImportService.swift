import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum ImportService {
    enum ImportError: LocalizedError {
        case unsupported
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported: return "Unsupported file type"
            case .failed(let message): return message
            }
        }
    }

    static func nextPosition(in board: Board) -> Int {
        (board.connections.map(\.position).max() ?? -1) + 1
    }

    static func connect(block: Block, to board: Board, context: ModelContext) {
        if board.connections.contains(where: { $0.block?.id == block.id }) { return }
        let connection = Connection(board: board, block: block, position: nextPosition(in: board))
        context.insert(connection)
        board.updatedAt = .now
    }

    static func connect(nestedBoard: Board, to board: Board, context: ModelContext) {
        guard nestedBoard.id != board.id else { return }
        if board.connections.contains(where: { $0.nestedBoard?.id == nestedBoard.id }) { return }
        let connection = Connection(board: board, nestedBoard: nestedBoard, position: nextPosition(in: board))
        context.insert(connection)
        board.updatedAt = .now
    }

    static func importFiles(_ urls: [URL], into board: Board, context: ModelContext) async throws {
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            try await importFile(url, into: board, context: context)
        }
    }

    static func importFile(_ url: URL, into board: Board, context: ModelContext) async throws {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let blockID = UUID()

        if let type, type.conforms(to: .image) {
            let dest = try MediaLibrary.copyFile(url, into: blockID)
            let (w, h) = ThumbnailService.imageDimensions(at: dest)
            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let size = attrs[.size] as? Int64 ?? 0
            let thumb = try ThumbnailService.generateImageThumbnail(from: dest, blockID: blockID)
            let block = Block(
                id: blockID,
                kind: .image,
                title: url.deletingPathExtension().lastPathComponent,
                sourceURL: url.absoluteString,
                localRelativePath: MediaLibrary.relativePath(from: dest),
                thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
                mimeType: type.preferredMIMEType ?? "image/\(url.pathExtension.lowercased())",
                byteSize: size,
                width: w,
                height: h
            )
            context.insert(block)
            connect(block: block, to: board, context: context)
            return
        }

        if let type, type.conforms(to: .movie) || type.conforms(to: .audiovisualContent),
           ["mp4", "mov", "m4v", "webm", "avi", "mkv"].contains(url.pathExtension.lowercased())
            || (type.conforms(to: .movie)) {
            let dest = try MediaLibrary.copyFile(url, into: blockID)
            let meta = await ThumbnailService.videoMetadata(at: dest)
            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let size = attrs[.size] as? Int64 ?? 0
            let thumb = try await ThumbnailService.generateVideoThumbnail(from: dest, blockID: blockID)
            let block = Block(
                id: blockID,
                kind: .video,
                title: url.deletingPathExtension().lastPathComponent,
                sourceURL: url.absoluteString,
                localRelativePath: MediaLibrary.relativePath(from: dest),
                thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
                mimeType: type.preferredMIMEType ?? "video/\(url.pathExtension.lowercased())",
                byteSize: size,
                width: meta.width,
                height: meta.height,
                duration: meta.duration
            )
            context.insert(block)
            connect(block: block, to: board, context: context)
            return
        }

        throw ImportError.unsupported
    }

    static func importURLString(_ string: String, into board: Board, context: ModelContext) async throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if ArenaService.isArenaChannelURL(trimmed) {
            let preview = try await ArenaService.fetchFromURLString(trimmed)
            let block = Block(
                kind: .arenaChannel,
                title: preview.title,
                sourceURL: preview.url.absoluteString,
                arenaSlug: preview.slug,
                arenaURL: preview.url.absoluteString,
                arenaOwnerName: preview.ownerName,
                arenaBlockCount: preview.blockCount,
                arenaUpdatedAt: preview.updatedAt
            )
            context.insert(block)
            connect(block: block, to: board, context: context)
            return
        }

        let remote = try await URLImportService.fetch(trimmed)
        let blockID = UUID()

        switch remote.kind {
        case .image:
            guard let data = remote.data else { throw ImportError.failed("Empty image data") }
            let dest = try MediaLibrary.writeData(data, into: blockID, filename: remote.filename)
            let (w, h) = ThumbnailService.imageDimensions(at: dest)
            let thumb = try ThumbnailService.generateImageThumbnail(from: dest, blockID: blockID)
            let block = Block(
                id: blockID,
                kind: .image,
                title: remote.title,
                sourceURL: remote.sourceURL.absoluteString,
                localRelativePath: MediaLibrary.relativePath(from: dest),
                thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
                mimeType: remote.mimeType,
                byteSize: Int64(data.count),
                width: w,
                height: h
            )
            context.insert(block)
            connect(block: block, to: board, context: context)

        case .video:
            guard let data = remote.data else { throw ImportError.failed("Empty video data") }
            let dest = try MediaLibrary.writeData(data, into: blockID, filename: remote.filename)
            let meta = await ThumbnailService.videoMetadata(at: dest)
            let thumb = try await ThumbnailService.generateVideoThumbnail(from: dest, blockID: blockID)
            let block = Block(
                id: blockID,
                kind: .video,
                title: remote.title,
                sourceURL: remote.sourceURL.absoluteString,
                localRelativePath: MediaLibrary.relativePath(from: dest),
                thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
                mimeType: remote.mimeType,
                byteSize: Int64(data.count),
                width: meta.width,
                height: meta.height,
                duration: meta.duration
            )
            context.insert(block)
            connect(block: block, to: board, context: context)

        case .link:
            let block = Block(
                kind: .link,
                title: remote.title,
                sourceURL: remote.sourceURL.absoluteString,
                mimeType: remote.mimeType
            )
            context.insert(block)
            connect(block: block, to: board, context: context)
        }
    }

    static func importPasteboard(into board: Board, context: ModelContext) async throws {
        let pb = NSPasteboard.general

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let fileURLs = urls.filter { $0.isFileURL }
            if !fileURLs.isEmpty {
                try await importFiles(fileURLs, into: board, context: context)
                return
            }
            for url in urls where !url.isFileURL {
                try await importURLString(url.absoluteString, into: board, context: context)
            }
            return
        }

        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            let blockID = UUID()
            let dest = try MediaLibrary.writeData(data, into: blockID, filename: "pasteboard.png")
            let (w, h) = ThumbnailService.imageDimensions(at: dest)
            let thumb = try ThumbnailService.generateImageThumbnail(from: dest, blockID: blockID)
            let block = Block(
                id: blockID,
                kind: .image,
                title: "Pasted image",
                localRelativePath: MediaLibrary.relativePath(from: dest),
                thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
                mimeType: "image/png",
                byteSize: Int64(data.count),
                width: w,
                height: h
            )
            context.insert(block)
            connect(block: block, to: board, context: context)
            return
        }

        if let string = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            if string.hasPrefix("http://") || string.hasPrefix("https://") {
                try await importURLString(string, into: board, context: context)
            } else {
                addTextBlock(string, title: "", into: board, context: context)
            }
            return
        }

        throw ImportError.failed("Nothing to paste")
    }

    static func addTextBlock(_ body: String, title: String, into board: Board, context: ModelContext) {
        let block = Block(kind: .text, title: title, textBody: body)
        context.insert(block)
        connect(block: block, to: board, context: context)
    }

    static func removeConnection(_ connection: Connection, deleteOrphanedBlock: Bool, context: ModelContext) {
        let block = connection.block
        let board = connection.board
        context.delete(connection)
        board?.updatedAt = .now

        if deleteOrphanedBlock, let block, block.connections.isEmpty {
            if block.localRelativePath != nil {
                MediaLibrary.removeBlockFiles(block.id)
            }
            context.delete(block)
        }
    }
}
