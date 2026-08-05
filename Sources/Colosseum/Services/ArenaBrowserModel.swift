import Foundation
import Observation

struct ArenaBrowseTarget: Hashable, Sendable {
    let slug: String
    let title: String?
    let urlString: String?

    init(slug: String, title: String? = nil, urlString: String? = nil) {
        self.slug = slug
        self.title = title
        self.urlString = urlString
    }

    init(block: Block) {
        self.slug = block.arenaSlug ?? ""
        self.title = block.title
        self.urlString = block.arenaURL ?? block.sourceURL
    }
}

@MainActor
@Observable
final class ArenaBrowserModel {
    private(set) var channel: ArenaChannelPreview?
    private(set) var items: [ArenaContentItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasMore = false
    private(set) var totalCount: Int?

    private var page = 0
    private var loadTask: Task<Void, Never>?

    var title: String {
        channel?.title ?? "Are.na"
    }

    var subtitle: String {
        if let channel {
            var parts = ["by \(channel.ownerName)"]
            if let totalCount {
                parts.append("\(totalCount) blocks")
            } else if channel.blockCount > 0 {
                parts.append("\(channel.blockCount) blocks")
            }
            parts.append("preview · not downloaded")
            return parts.joined(separator: " · ")
        }
        return "Loading…"
    }

    func load(_ target: ArenaBrowseTarget) {
        loadTask?.cancel()
        channel = nil
        items = []
        page = 0
        hasMore = false
        totalCount = nil
        errorMessage = nil
        isLoading = true

        loadTask = Task {
            do {
                let preview: ArenaChannelPreview
                if let urlString = target.urlString, ArenaService.isArenaChannelURL(urlString) {
                    preview = try await ArenaService.fetchFromURLString(urlString)
                } else {
                    preview = try await ArenaService.fetchChannel(slug: target.slug)
                }
                guard !Task.isCancelled else { return }
                channel = preview
                try await fetchNextPage(reset: true)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadMoreIfNeeded(currentItem: ArenaContentItem?) {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard let currentItem else {
            Task { try? await fetchNextPage(reset: false) }
            return
        }
        guard let index = items.firstIndex(of: currentItem), index >= items.count - 6 else { return }
        Task { try? await fetchNextPage(reset: false) }
    }

    func refresh() {
        guard let channel else { return }
        load(ArenaBrowseTarget(slug: channel.slug, title: channel.title, urlString: channel.url.absoluteString))
    }

    func loadAllRemaining() async {
        while hasMore, !Task.isCancelled {
            do {
                try await fetchNextPage(reset: false)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    private func fetchNextPage(reset: Bool) async throws {
        guard let channel else { return }
        if reset {
            isLoading = true
            page = 0
            items = []
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        let nextPage = page + 1
        let result = try await ArenaService.fetchContentsPage(slug: channel.slug, page: nextPage, perPage: 24)
        guard !Task.isCancelled else { return }
        page = nextPage
        hasMore = result.hasMore
        totalCount = result.totalCount ?? totalCount
        if reset {
            items = result.items
        } else {
            let existing = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { !existing.contains($0.id) })
        }
        errorMessage = nil
    }
}
