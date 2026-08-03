import Foundation

struct ArenaChannelPreview: Sendable {
    let slug: String
    let title: String
    let ownerName: String
    let ownerSlug: String
    let blockCount: Int
    let updatedAt: Date?
    let url: URL
    let notes: String
}

struct ArenaContentItem: Sendable, Identifiable, Hashable {
    enum Kind: String, Sendable {
        case image
        case attachment
        case link
        case text
        case channel
        case other
    }

    let id: Int
    let kind: Kind
    let typeName: String
    let title: String
    let notes: String
    let sourceURL: String?
    let imageURL: String?
    let thumbURL: String?
    let imageWidth: Int
    let imageHeight: Int
    let imageMime: String?
    let imageFilename: String?
    let imageBytes: Int64
    let attachmentURL: String?
    let attachmentMime: String?
    let attachmentFilename: String?
    let attachmentBytes: Int64
    let textBody: String
    let channelSlug: String?
    let channelOwnerName: String?
    let channelOwnerSlug: String?
    let channelBlockCount: Int
    let channelUpdatedAt: Date?
    let position: Int

    var isVideo: Bool {
        if let mime = attachmentMime?.lowercased(), mime.hasPrefix("video/") { return true }
        if let name = attachmentFilename?.lowercased() {
            let ext = name.split(separator: ".").last.map(String.init) ?? ""
            return ["mp4", "mov", "m4v", "webm"].contains(ext)
        }
        return false
    }

    /// Best URL for a full remote preview (original image, video file, or link).
    var previewURL: String? {
        if isVideo { return attachmentURL }
        if kind == .image || kind == .link || kind == .attachment {
            return imageURL ?? attachmentURL ?? sourceURL
        }
        if kind == .channel {
            guard let slug = channelSlug else { return nil }
            let owner = channelOwnerSlug ?? "are.na"
            return "https://www.are.na/\(owner)/\(slug)"
        }
        return sourceURL
    }

    var gridImageURL: String? {
        thumbURL ?? imageURL
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if kind == .text {
            let first = textBody.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            return first.isEmpty ? "Text" : first
        }
        return typeName
    }
}

enum ArenaService {
    private static let apiBase = URL(string: "https://api.are.na/v3/channels/")!

    /// Parses Are.na channel URLs like:
    /// - https://www.are.na/user-slug/channel-slug
    /// - https://are.na/user-slug/channel-slug
    static func parseChannelURL(_ string: String) -> (userSlug: String?, channelSlug: String)? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host == "are.na" || host == "www.are.na"
        else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let reserved = Set(["about", "blog", "tools", "settings", "explore", "feed", "search"])
        if reserved.contains(parts[0].lowercased()) { return nil }
        return (parts[0], parts[1])
    }

    static func isArenaChannelURL(_ string: String) -> Bool {
        parseChannelURL(string) != nil
    }

    static func fetchChannel(slug: String) async throws -> ArenaChannelPreview {
        let url = apiBase.appendingPathComponent(slug)
        let data = try await get(url)
        let decoded = try JSONDecoder().decode(ArenaChannelDTO.self, from: data)
        return preview(from: decoded)
    }

    static func fetchFromURLString(_ string: String) async throws -> ArenaChannelPreview {
        guard let parsed = parseChannelURL(string) else {
            throw URLError(.badURL)
        }
        return try await fetchChannel(slug: parsed.channelSlug)
    }

    struct ContentsPage: Sendable {
        let items: [ArenaContentItem]
        let page: Int
        let hasMore: Bool
        let totalCount: Int?
    }

    static func fetchContentsPage(slug: String, page: Int = 1, perPage: Int = 24) async throws -> ContentsPage {
        var components = URLComponents(
            url: apiBase.appendingPathComponent(slug).appendingPathComponent("contents"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per", value: String(perPage))
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await get(url)
        let decoded = try JSONDecoder().decode(ArenaContentsPageDTO.self, from: data)
        let hasMore = decoded.meta.has_more_pages == true || decoded.meta.next_page != nil
        return ContentsPage(
            items: decoded.data.map { $0.asContentItem() },
            page: page,
            hasMore: hasMore,
            totalCount: decoded.meta.total_count
        )
    }

    /// Fetches every page of channel contents (public channels only).
    static func fetchAllContents(slug: String, perPage: Int = 50) async throws -> [ArenaContentItem] {
        var page = 1
        var items: [ArenaContentItem] = []
        while true {
            let result = try await fetchContentsPage(slug: slug, page: page, perPage: perPage)
            items.append(contentsOf: result.items)
            guard result.hasMore else { break }
            page += 1
            if page > 200 { break }
        }
        return items
    }

    static func download(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Colosseum/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ArenaError.privateOrUnavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func preview(from decoded: ArenaChannelDTO) -> ArenaChannelPreview {
        let pageURL = URL(string: "https://www.are.na/\(decoded.owner.slug)/\(decoded.slug)")
            ?? URL(string: "https://www.are.na/\(decoded.slug)")!
        return ArenaChannelPreview(
            slug: decoded.slug,
            title: decoded.title,
            ownerName: decoded.owner.name,
            ownerSlug: decoded.owner.slug,
            blockCount: decoded.counts.contents ?? decoded.counts.blocks,
            updatedAt: parseDate(decoded.updated_at),
            url: pageURL,
            notes: decoded.description?.plain
                ?? decoded.description?.markdown
                ?? ""
        )
    }

    fileprivate static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

enum ArenaError: LocalizedError {
    case privateOrUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .privateOrUnavailable:
            return "This Are.na channel is private or unavailable without authentication."
        case .failed(let message):
            return message
        }
    }
}

// MARK: - DTOs

private struct ArenaChannelDTO: Decodable {
    let slug: String
    let title: String
    let updated_at: String
    let owner: Owner
    let counts: Counts
    let description: MarkdownBlob?

    struct Owner: Decodable {
        let name: String
        let slug: String
    }

    struct Counts: Decodable {
        let blocks: Int
        let contents: Int?
    }
}

private struct MarkdownBlob: Decodable {
    let markdown: String?
    let plain: String?
}

private struct ArenaContentsPageDTO: Decodable {
    let meta: Meta
    let data: [ArenaContentDTO]

    struct Meta: Decodable {
        let next_page: Int?
        let has_more_pages: Bool?
        let total_count: Int?
    }
}

private struct ArenaContentDTO: Decodable {
    let id: Int
    let type: String
    let title: String?
    let description: MarkdownBlob?
    let content: MarkdownBlob?
    let source: Source?
    let image: ImageInfo?
    let attachment: AttachmentInfo?
    let slug: String?
    let owner: Owner?
    let counts: Counts?
    let updated_at: String?
    let connection: ConnectionInfo?

    struct Source: Decodable {
        let url: String?
        let title: String?
    }

    struct ImageInfo: Decodable {
        let src: String?
        let width: Int?
        let height: Int?
        let content_type: String?
        let filename: String?
        let file_size: Int64?
        let small: ImageVariant?
        let medium: ImageVariant?

        struct ImageVariant: Decodable {
            let src: String?
        }
    }

    struct AttachmentInfo: Decodable {
        let url: String?
        let content_type: String?
        let filename: String?
        let file_size: Int64?
        let file_extension: String?
    }

    struct Owner: Decodable {
        let name: String?
        let slug: String?
    }

    struct Counts: Decodable {
        let blocks: Int?
        let contents: Int?
    }

    struct ConnectionInfo: Decodable {
        let position: Int?
    }

    func asContentItem() -> ArenaContentItem {
        let kind: ArenaContentItem.Kind
        switch type {
        case "Image": kind = .image
        case "Attachment": kind = .attachment
        case "Link": kind = .link
        case "Text": kind = .text
        case "Channel": kind = .channel
        default: kind = .other
        }

        let notes = description?.plain ?? description?.markdown ?? ""
        let textBody = content?.plain ?? content?.markdown ?? ""

        let thumb = image?.small?.src ?? image?.medium?.src ?? image?.src

        return ArenaContentItem(
            id: id,
            kind: kind,
            typeName: type,
            title: title ?? source?.title ?? "",
            notes: notes,
            sourceURL: source?.url,
            imageURL: image?.src,
            thumbURL: thumb,
            imageWidth: image?.width ?? 0,
            imageHeight: image?.height ?? 0,
            imageMime: image?.content_type,
            imageFilename: image?.filename,
            imageBytes: image?.file_size ?? 0,
            attachmentURL: attachment?.url,
            attachmentMime: attachment?.content_type,
            attachmentFilename: attachment?.filename,
            attachmentBytes: attachment?.file_size ?? 0,
            textBody: textBody,
            channelSlug: slug,
            channelOwnerName: owner?.name,
            channelOwnerSlug: owner?.slug,
            channelBlockCount: counts?.contents ?? counts?.blocks ?? 0,
            channelUpdatedAt: ArenaService.parseDate(updated_at),
            position: connection?.position ?? 0
        )
    }
}
