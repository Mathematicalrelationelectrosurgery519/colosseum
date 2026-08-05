import AppKit
import Foundation

@MainActor
enum BlockClipboard {
    /// Copies the block's media or text onto the general pasteboard.
    @discardableResult
    static func copy(_ block: Block) -> Bool {
        switch block.kind {
        case .text:
            return copyText(block.textBody)

        case .image:
            guard let url = localFileURL(for: block) else {
                return copyURLString(block.remoteMediaURL ?? block.sourceURL)
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            // Write raw GIF bytes first so paste destinations keep animation.
            if AnimatedImage.isGIF(url: url), let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .init("com.compuserve.gif"))
                pb.writeObjects([url as NSURL])
                return true
            }
            var items: [NSPasteboardWriting] = [url as NSURL]
            if let image = NSImage(contentsOf: url) {
                items.insert(image, at: 0)
            }
            return pb.writeObjects(items)

        case .video:
            guard let url = localFileURL(for: block) else {
                return copyURLString(block.remoteMediaURL ?? block.sourceURL)
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            return pb.writeObjects([url as NSURL])

        case .audio:
            guard let url = localFileURL(for: block) else {
                return copyURLString(block.remoteMediaURL ?? block.sourceURL)
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            return pb.writeObjects([url as NSURL])

        case .link:
            return copyURLString(block.sourceURL)

        case .arenaChannel:
            return copyURLString(block.arenaURL ?? block.sourceURL)
        }
    }

    /// Copies a remote Are.na item (text, cached image when available, otherwise URL).
    @discardableResult
    static func copy(_ item: ArenaContentItem) -> Bool {
        switch item.kind {
        case .text:
            return copyText(item.textBody)

        case .image:
            return copyRemoteImage(item)

        case .attachment:
            if item.isVideo || item.isAudio {
                return copyURLString(item.attachmentURL ?? item.sourceURL)
            }
            return copyRemoteImage(item) || copyURLString(item.attachmentURL ?? item.sourceURL)

        case .link:
            return copyURLString(item.sourceURL ?? item.previewURL)

        case .channel:
            return copyURLString(item.previewURL)

        case .other:
            return copyURLString(item.previewURL ?? item.sourceURL)
        }
    }

    private static func localFileURL(for block: Block) -> URL? {
        guard let path = block.localRelativePath else { return nil }
        let url = MediaLibrary.absoluteURL(relativePath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func copyText(_ body: String) -> Bool {
        guard !body.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(body, forType: .string)
        return true
    }

    private static func copyRemoteImage(_ item: ArenaContentItem) -> Bool {
        let candidates = [item.imageURL, item.thumbURL, item.attachmentURL].compactMap { $0 }
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url)),
               let image = NSImage(data: cached.data) {
                let pb = NSPasteboard.general
                pb.clearContents()
                return pb.writeObjects([image, url as NSURL])
            }
        }
        return copyURLString(item.imageURL ?? item.previewURL)
    }

    private static func copyURLString(_ source: String?) -> Bool {
        guard let source, !source.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(source, forType: .string)
        if let url = URL(string: source) {
            pb.writeObjects([url as NSURL])
        }
        return true
    }
}
