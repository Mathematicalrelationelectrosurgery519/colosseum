import AppKit
import Foundation
import UniformTypeIdentifiers

struct RemoteMediaResult: Sendable {
    enum Kind { case image, video, audio, link }
    let kind: Kind
    let data: Data?
    let filename: String
    let mimeType: String?
    let title: String
    let sourceURL: URL
}

enum URLImportService {
    static func fetch(_ urlString: String) async throws -> RemoteMediaResult {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Colosseum/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let mime = http?.mimeType?.lowercased()
        let suggested = http?.suggestedFilename ?? url.lastPathComponent

        if let mime, mime.hasPrefix("image/") {
            let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "jpg"
            let name = suggested.contains(".") ? suggested : "\(suggested).\(ext)"
            return RemoteMediaResult(
                kind: .image,
                data: data,
                filename: name,
                mimeType: mime,
                title: name,
                sourceURL: url
            )
        }

        if let mime, mime.hasPrefix("video/") {
            let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "mp4"
            let name = suggested.contains(".") ? suggested : "\(suggested).\(ext)"
            return RemoteMediaResult(
                kind: .video,
                data: data,
                filename: name,
                mimeType: mime,
                title: name,
                sourceURL: url
            )
        }

        if let mime, mime.hasPrefix("audio/") {
            let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "mp3"
            let name = suggested.contains(".") ? suggested : "\(suggested).\(ext)"
            return RemoteMediaResult(
                kind: .audio,
                data: data,
                filename: name,
                mimeType: mime,
                title: name,
                sourceURL: url
            )
        }

        // Path extension fallback
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "tif", "tiff"].contains(ext) {
            return RemoteMediaResult(
                kind: .image,
                data: data,
                filename: suggested.isEmpty ? "image.\(ext)" : suggested,
                mimeType: mime ?? "image/\(ext)",
                title: suggested,
                sourceURL: url
            )
        }
        if ["mp4", "mov", "m4v", "webm"].contains(ext) {
            return RemoteMediaResult(
                kind: .video,
                data: data,
                filename: suggested.isEmpty ? "video.\(ext)" : suggested,
                mimeType: mime ?? "video/\(ext)",
                title: suggested,
                sourceURL: url
            )
        }
        if ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus"].contains(ext) {
            return RemoteMediaResult(
                kind: .audio,
                data: data,
                filename: suggested.isEmpty ? "audio.\(ext)" : suggested,
                mimeType: mime ?? "audio/\(ext)",
                title: suggested,
                sourceURL: url
            )
        }

        let title = extractHTMLTitle(from: data) ?? url.host ?? url.absoluteString
        return RemoteMediaResult(
            kind: .link,
            data: nil,
            filename: "",
            mimeType: mime,
            title: title,
            sourceURL: url
        )
    }

    private static func extractHTMLTitle(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        if let og = match(pattern: #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#, in: html)
            ?? match(pattern: #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#, in: html) {
            return decodeHTMLEntities(og)
        }
        if let title = match(pattern: #"<title[^>]*>(.*?)</title>"#, in: html) {
            return decodeHTMLEntities(title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func match(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: range),
              result.numberOfRanges > 1,
              let swiftRange = Range(result.range(at: 1), in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return string }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return string
    }
}
