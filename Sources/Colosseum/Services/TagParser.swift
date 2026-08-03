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
        var seen = Set<String>()
        var ordered: [String] = []
        for connection in board.sortedConnections {
            let texts: [String]
            if let block = connection.block {
                texts = [block.notes]
            } else if let nested = connection.nestedBoard {
                texts = [nested.notes]
            } else {
                texts = []
            }
            for text in texts {
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
