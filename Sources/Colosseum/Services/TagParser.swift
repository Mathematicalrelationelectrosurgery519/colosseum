import Foundation

enum TagMatchMode: String, CaseIterable, Identifiable {
    case intersection
    case union

    var id: String { rawValue }

    var label: String {
        switch self {
        case .intersection: return "And"
        case .union: return "Or"
        }
    }
}

enum TagParser {
    /// Matches `#tag`, `#tag-name`, `#tag_name` (not email-like mid-word).
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![\w/])#([A-Za-z0-9][A-Za-z0-9_-]*)"#,
        options: []
    )

    static func tags(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = pattern.matches(in: text, options: [], range: range)
        var seen = Set<String>()
        var ordered: [String] = []
        for match in matches {
            guard match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: text)
            else { continue }
            let raw = String(text[swiftRange])
            let key = normalize(raw)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(raw)
        }
        return ordered
    }

    static func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }

    static func displayLabel(_ tag: String) -> String {
        let trimmed = tag.hasPrefix("#") ? tag : "#\(tag)"
        return trimmed
    }

    /// Appends `#tag` to notes if not already present. Idempotent by normalized key.
    static func appendingTag(_ tag: String, to notes: String) -> String {
        let key = normalize(tag)
        guard !key.isEmpty else { return notes }
        let existing = Set(tags(in: notes).map(normalize))
        guard !existing.contains(key) else { return notes }
        let token = displayLabel(tag)
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? token : trimmed + " " + token
    }

    /// Removes `#tag` tokens (case-insensitive) from notes.
    static func removingTag(_ tag: String, from notes: String) -> String {
        let key = normalize(tag)
        guard !key.isEmpty else { return notes }
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = try! NSRegularExpression(
            pattern: #"(?<![\w/])#"# + escaped + #"(?![A-Za-z0-9_-])"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(notes.startIndex..<notes.endIndex, in: notes)
        var result = pattern.stringByReplacingMatches(in: notes, options: [], range: range, withTemplate: "")
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Header order: currently selected tags (by selection order), then the rest alphabetically.
    static func displayedTags(
        _ tags: [String],
        selected: Set<String>,
        selectionOrder: [String]
    ) -> [String] {
        let naturalKeys = Dictionary(
            uniqueKeysWithValues: tags.map { (normalize($0), $0) }
        )
        let selectedFront = selectionOrder.compactMap { naturalKeys[$0] }
        let unselected = tags.filter { !selected.contains(normalize($0)) }
        return selectedFront + unselected
    }

    /// Collect unique tags from board connections (block notes + nested board notes).
    static func boardTags(from board: Board) -> [String] {
        boardTags(from: board.sortedConnections)
    }

    /// Collect unique tags from an already-sorted connection list (avoids re-sorting).
    static func boardTags(from connections: [Connection]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for connection in connections {
            for text in noteTexts(for: connection) {
                for tag in tags(in: text) {
                    let key = normalize(tag)
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    ordered.append(tag)
                }
            }
        }
        return ordered.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Normalized tag key → number of board items (connections) that include the tag.
    static func boardTagItemCounts(from board: Board) -> [String: Int] {
        boardTagItemCounts(from: board.sortedConnections)
    }

    /// Normalized tag key → item counts from an already-sorted connection list.
    static func boardTagItemCounts(from connections: [Connection]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for connection in connections {
            for key in tags(for: connection) {
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    /// Board tags ranked by item count (desc), then alphabetically.
    static func popularBoardTags(from board: Board) -> [String] {
        popularBoardTags(from: board.sortedConnections)
    }

    /// Popularity-ranked tags from an already-sorted connection list (single sort + single scan).
    static func popularBoardTags(from connections: [Connection]) -> [String] {
        boardTagSuggestions(from: connections).tags
    }

    /// Ranked tags and per-tag item counts from one connection scan.
    static func boardTagSuggestions(from connections: [Connection]) -> (tags: [String], counts: [String: Int]) {
        let itemCounts = boardTagItemCounts(from: connections)
        var displayByKey: [String: String] = [:]
        for connection in connections {
            for text in noteTexts(for: connection) {
                for tag in tags(in: text) {
                    let key = normalize(tag)
                    if displayByKey[key] == nil {
                        displayByKey[key] = tag
                    }
                }
            }
        }
        let tags = displayByKey.keys
            .sorted {
                let c0 = itemCounts[$0] ?? 0
                let c1 = itemCounts[$1] ?? 0
                if c0 != c1 { return c0 > c1 }
                let d0 = displayByKey[$0] ?? $0
                let d1 = displayByKey[$1] ?? $1
                return d0.localizedCaseInsensitiveCompare(d1) == .orderedAscending
            }
            .compactMap { displayByKey[$0] }
        return (tags, itemCounts)
    }

    /// Prefix filter over a popularity-ranked list. Empty query → top `limit` tags.
    static func autocomplete(query: String, from ranked: [String], limit: Int = 3) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(ranked.prefix(limit))
        }
        let q = normalize(trimmed)
        return Array(
            ranked
                .filter { normalize($0).hasPrefix(q) }
                .prefix(limit)
        )
    }

    /// Active `#tag` being typed at `caret` (UTF-16 index), or nil if not in a tag token.
    static func activeTagEdit(in text: String, caret: Int) -> (range: NSRange, query: String)? {
        let ns = text as NSString
        let length = ns.length
        guard caret >= 0, caret <= length else { return nil }

        var i = caret
        while i > 0 {
            let scalar = ns.character(at: i - 1)
            if isTagBodyCharacter(scalar) {
                i -= 1
                continue
            }
            if scalar == 35 { // '#'
                if i >= 2 {
                    let before = ns.character(at: i - 2)
                    if isWordCharacter(before) { return nil }
                }
                let start = i - 1
                let query = ns.substring(with: NSRange(location: i, length: caret - i))
                return (NSRange(location: start, length: caret - start), query)
            }
            return nil
        }
        return nil
    }

    private static func noteTexts(for connection: Connection) -> [String] {
        if let block = connection.block {
            return [block.notes]
        }
        if let nested = connection.nestedBoard {
            return [nested.notes]
        }
        return []
    }

    private static func isTagBodyCharacter(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) // A-Z
            || (c >= 97 && c <= 122) // a-z
            || (c >= 48 && c <= 57) // 0-9
            || c == 95 || c == 45 // _ -
    }

    private static func isWordCharacter(_ c: unichar) -> Bool {
        isTagBodyCharacter(c) || c == 47 // '/'
    }

    static func tags(for connection: Connection) -> Set<String> {
        if let block = connection.block {
            return Set(tags(in: block.notes).map(normalize))
        }
        if let nested = connection.nestedBoard {
            return Set(tags(in: nested.notes).map(normalize))
        }
        return []
    }

    static func matches(
        connection: Connection,
        selected: Set<String>,
        mode: TagMatchMode
    ) -> Bool {
        guard !selected.isEmpty else { return true }
        let tags = tags(for: connection)
        switch mode {
        case .intersection:
            return selected.isSubset(of: tags)
        case .union:
            return !selected.isDisjoint(with: tags)
        }
    }
}
