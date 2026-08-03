import SwiftUI

/// Anchor of the grid cell currently elevated for tag assign.
enum TagAssignAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Compact tag picker shown beneath a focused block during keyboard assign (T).
struct TagAssignPopover: View {
    let tags: [String]
    /// Normalized keys currently applied / picked for the block.
    let selectedKeys: Set<String>
    /// Normalized key under keyboard cursor.
    let focusedKey: String?
    var onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tags.isEmpty {
                Text("No tags on this board")
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        let key = TagParser.normalize(tag)
                        TagPill(
                            tag: tag,
                            isSelected: selectedKeys.contains(key),
                            isFocused: focusedKey == key
                        ) {
                            onToggle(tag)
                        }
                        .id(key)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minWidth: 140, maxWidth: 220, alignment: .leading)
        .background(ColosseumTheme.surface)
        .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}
