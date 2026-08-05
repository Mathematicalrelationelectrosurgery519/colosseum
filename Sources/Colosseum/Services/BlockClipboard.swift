import AppKit
import Foundation

@MainActor
enum BlockClipboard {
    /// Copies the block's media or text onto the general pasteboard.
    /// Remote media is fetched asynchronously; returns true once the copy is started or completed.
    @discardableResult
    static func copy(_ block: Block) -> Bool {
        switch block.kind {
        case .text:
            return copyText(block.textBody)

        case .image:
            if let url = localFileURL(for: block) {
                return copyLocalImage(at: url)
            }
            guard let remote = block.remoteMediaURL ?? block.sourceURL, !remote.isEmpty else {
                return false
            }
            Task { await copyRemoteImage(urlString: remote) }
            return true

        case .video:
            if let url = localFileURL(for: block) {
                return copyLocalFile(at: url)
            }
            guard let remote = block.remoteMediaURL ?? block.sourceURL, !remote.isEmpty else {
                return false
            }
            Task { await copyRemoteFile(urlString: remote) }
            return true

        case .audio:
            if let url = localFileURL(for: block) {
                return copyLocalFile(at: url)
            }
            guard let remote = block.remoteMediaURL ?? block.sourceURL, !remote.isEmpty else {
                return false
            }
            Task { await copyRemoteFile(urlString: remote) }
            return true

        case .link:
            return copyURLString(block.sourceURL)

        case .arenaChannel:
            return copyURLString(block.arenaURL ?? block.sourceURL)
        }
    }

    /// Copies a remote Are.na item (text, fetched image/file, otherwise URL).
    @discardableResult
    static func copy(_ item: ArenaContentItem) -> Bool {
        switch item.kind {
        case .text:
            return copyText(item.textBody)

        case .image:
            return beginRemoteImageCopy(item)

        case .attachment:
            if item.isVideo || item.isAudio {
                guard let remote = item.attachmentURL ?? item.sourceURL, !remote.isEmpty else {
                    return false
                }
                Task { await copyRemoteFile(urlString: remote) }
                return true
            }
            return beginRemoteImageCopy(item)

        case .link:
            return copyURLString(item.sourceURL ?? item.previewURL)

        case .channel:
            return copyURLString(item.previewURL)

        case .other:
            return copyURLString(item.previewURL ?? item.sourceURL)
        }
    }

    // MARK: - Local

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

    private static func copyLocalImage(at url: URL) -> Bool {
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
    }

    private static func copyLocalFile(at url: URL) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([url as NSURL])
    }

    // MARK: - Remote

    private static func beginRemoteImageCopy(_ item: ArenaContentItem) -> Bool {
        let candidates = [item.imageURL, item.attachmentURL, item.thumbURL].compactMap { $0 }
        guard let remote = candidates.first(where: { !$0.isEmpty }) else {
            return copyURLString(item.previewURL)
        }
        Task { await copyRemoteImage(urlString: remote) }
        return true
    }

    private static func copyRemoteImage(urlString: String) async {
        do {
            let data = try await ArenaService.download(urlString)
            writeImageData(data, sourceURL: URL(string: urlString))
        } catch {
            _ = copyURLString(urlString)
        }
    }

    private static func copyRemoteFile(urlString: String) async {
        do {
            let data = try await ArenaService.download(urlString)
            let remoteURL = URL(string: urlString)
            let ext = remoteURL?.pathExtension.nilIfEmpty
                ?? suggestedExtension(for: data)
                ?? "bin"
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("colosseum-clipboard-\(UUID().uuidString).\(ext)")
            try data.write(to: temp, options: .atomic)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([temp as NSURL])
            if let remoteURL {
                pb.setString(remoteURL.absoluteString, forType: .string)
            }
        } catch {
            _ = copyURLString(urlString)
        }
    }

    private static func writeImageData(_ data: Data, sourceURL: URL?) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if AnimatedImage.isGIF(data: data) {
            pb.setData(data, forType: .init("com.compuserve.gif"))
            if let sourceURL {
                pb.writeObjects([sourceURL as NSURL])
            }
            return
        }

        guard let image = NSImage(data: data) else {
            _ = copyURLString(sourceURL?.absoluteString)
            return
        }

        var items: [NSPasteboardWriting] = [image]
        if let sourceURL {
            items.append(sourceURL as NSURL)
        }
        pb.writeObjects(items)
    }

    @discardableResult
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

    private static func suggestedExtension(for data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.count >= 12,
           data[0...3] == Data("RIFF".utf8),
           data[8...11] == Data("WEBP".utf8) {
            return "webp"
        }
        if data.count >= 12, data[4...7] == Data("ftyp".utf8) { return "mp4" }
        if data.starts(with: Data("ID3".utf8)) || data.starts(with: [0xFF, 0xFB]) { return "mp3" }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
