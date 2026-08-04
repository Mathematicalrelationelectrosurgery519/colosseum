import Foundation
import ImageIO

enum AnimatedImage {
    static func isGIF(mimeType: String?) -> Bool {
        mimeType?.lowercased() == "image/gif"
    }

    static func isGIF(url: URL) -> Bool {
        url.pathExtension.lowercased() == "gif"
    }

    static func isGIF(pathExtension: String) -> Bool {
        pathExtension.lowercased() == "gif"
    }

    static func isGIF(data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let header = data.prefix(6)
        return header.elementsEqual(Array("GIF87a".utf8))
            || header.elementsEqual(Array("GIF89a".utf8))
    }

    /// True when the file has more than one ImageIO frame (animated GIF/PNG/WebP).
    static func isAnimated(at url: URL) -> Bool {
        if isGIF(url: url) { return true }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }
}
