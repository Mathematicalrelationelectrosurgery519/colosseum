import AppKit
import SwiftUI

struct TagPill: View {
    let tag: String
    var isSelected: Bool
    var action: () -> Void

    private var color: Color { TagColor.color(for: tag) }

    var body: some View {
        Button(action: action) {
            Text(TagParser.displayLabel(tag))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? color : ColosseumTheme.tertiaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .animation(ColosseumMotion.soft, value: isSelected)
    }
}

/// Plain ∩/∪ glyph matching the column-density icon treatment.
struct TagMatchModeIcon: View {
    @Binding var mode: TagMatchMode

    var body: some View {
        Button {
            withAnimation(ColosseumMotion.soft) {
                mode = mode == .intersection ? .union : .intersection
            }
        } label: {
            Text(mode == .intersection ? "∩" : "∪")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(ColosseumTheme.tertiaryText)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            mode == .intersection
                ? "Intersection — items with every selected tag (N). Click for union."
                : "Union — items with any selected tag (U). Click for intersection."
        )
        .pointingHandCursor()
    }
}

/// Centered, horizontally scrollable tag strip for the board header.
struct TagHeaderScroller: View {
    let tags: [String]
    @Binding var selected: Set<String>
    @Binding var selectionOrder: [String]

    private var displayedTags: [String] {
        let natural = tags
        let naturalKeys = Dictionary(
            uniqueKeysWithValues: natural.map { (TagParser.normalize($0), $0) }
        )
        let selectedFront = selectionOrder.compactMap { naturalKeys[$0] }
        let unselected = natural.filter { !selected.contains(TagParser.normalize($0)) }
        return selectedFront + unselected
    }

    var body: some View {
        Group {
            if tags.isEmpty {
                Color.clear.frame(width: 1, height: 1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(displayedTags, id: \.self) { tag in
                            let key = TagParser.normalize(tag)
                            TagPill(tag: tag, isSelected: selected.contains(key)) {
                                toggle(tag)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: 520)
                .frame(height: ChromeMetrics.controlHeight)
            }
        }
        .animation(ColosseumMotion.soft, value: selectionOrder)
        .animation(ColosseumMotion.soft, value: selected)
    }

    private func toggle(_ tag: String) {
        let key = TagParser.normalize(tag)
        withAnimation(ColosseumMotion.soft) {
            if selected.contains(key) {
                selected.remove(key)
                selectionOrder.removeAll { $0 == key }
            } else {
                selected.insert(key)
                selectionOrder.removeAll { $0 == key }
                selectionOrder.insert(key, at: 0)
            }
        }
    }
}
