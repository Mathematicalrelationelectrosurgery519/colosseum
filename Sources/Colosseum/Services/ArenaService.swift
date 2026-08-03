import Foundation

struct ArenaChannelPreview: Sendable {
    let slug: String
    let title: String
    let ownerName: String
    let blockCount: Int
    let updatedAt: Date?
    let url: URL
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
        // Skip reserved first segments that aren't user slugs
        let reserved = Set(["about", "blog", "tools", "settings", "explore", "feed", "search"])
        if reserved.contains(parts[0].lowercased()) { return nil }
        return (parts[0], parts[1])
    }

    static func isArenaChannelURL(_ string: String) -> Bool {
        parseChannelURL(string) != nil
    }

    static func fetchChannel(slug: String) async throws -> ArenaChannelPreview {
        let url = apiBase.appendingPathComponent(slug)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ArenaChannelDTO.self, from: data)
        let pageURL = URL(string: "https://www.are.na/\(decoded.owner.slug)/\(decoded.slug)")
            ?? URL(string: "https://www.are.na/\(decoded.slug)")!

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var updated = formatter.date(from: decoded.updated_at)
        if updated == nil {
            formatter.formatOptions = [.withInternetDateTime]
            updated = formatter.date(from: decoded.updated_at)
        }

        return ArenaChannelPreview(
            slug: decoded.slug,
            title: decoded.title,
            ownerName: decoded.owner.name,
            blockCount: decoded.counts.blocks,
            updatedAt: updated,
            url: pageURL
        )
    }

    static func fetchFromURLString(_ string: String) async throws -> ArenaChannelPreview {
        guard let parsed = parseChannelURL(string) else {
            throw URLError(.badURL)
        }
        return try await fetchChannel(slug: parsed.channelSlug)
    }
}

private struct ArenaChannelDTO: Decodable {
    let slug: String
    let title: String
    let updated_at: String
    let owner: Owner
    let counts: Counts

    struct Owner: Decodable {
        let name: String
        let slug: String
    }

    struct Counts: Decodable {
        let blocks: Int
    }
}
