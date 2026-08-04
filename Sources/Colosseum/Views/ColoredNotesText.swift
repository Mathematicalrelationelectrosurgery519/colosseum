import AppKit
import SwiftUI

/// Notes text with Are.na-style `#tag` coloring (matches block preview notes).
enum ColoredNotesText {
    static func attributed(_ text: String, fontSize: CGFloat = 13) -> AttributedString {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard full.length > 0 else { return AttributedString("") }

        let pattern = try! NSRegularExpression(
            pattern: #"(?<![\w/])#([A-Za-z0-9][A-Za-z0-9_-]*)"#,
            options: []
        )
        let font = Font.system(size: fontSize)
        var output = AttributedString()
        var cursor = 0

        for match in pattern.matches(in: text, options: [], range: full) {
            if match.range.location > cursor {
                let range = NSRange(location: cursor, length: match.range.location - cursor)
                var plain = AttributedString(ns.substring(with: range))
                plain.font = font
                plain.foregroundColor = ColosseumTheme.secondaryText
                output += plain
            }
            let tag = ns.substring(with: match.range(at: 1))
            var tagged = AttributedString(ns.substring(with: match.range))
            tagged.font = font
            tagged.foregroundColor = TagColor.color(for: tag)
            output += tagged
            cursor = NSMaxRange(match.range)
        }

        if cursor < full.length {
            var plain = AttributedString(ns.substring(from: cursor))
            plain.font = font
            plain.foregroundColor = ColosseumTheme.secondaryText
            output += plain
        }

        return output
    }
}

/// Single truncated notes line under a grid block.
struct NotesPreviewLine: View {
    let text: String

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Text(ColoredNotesText.attributed(trimmed.isEmpty ? " " : trimmed, fontSize: 13))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(trimmed.isEmpty ? 0 : 1)
            .accessibilityHidden(trimmed.isEmpty)
    }
}

/// Square cell + optional one-line notes preview.
struct GridBlockChrome<Content: View>: View {
    let notes: String
    var isSelected: Bool = false
    var showsNotes: Bool = true
    /// When true, reports the square (not the notes line) for tag-assign elevation.
    var captureTagAssignAnchor: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: showsNotes ? 8 : 0) {
            content()
                .gridSelectionRing(isActive: isSelected)
                .anchorPreference(key: TagAssignAnchorKey.self, value: .bounds) {
                    captureTagAssignAnchor ? $0 : nil
                }

            if showsNotes {
                NotesPreviewLine(text: notes)
                    .frame(height: 16)
            }
        }
    }
}
