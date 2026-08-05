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
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 210)
                    .onAppear { scrollToFocused(using: proxy) }
                    .onChange(of: focusedKey) { _, _ in scrollToFocused(using: proxy) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: 176, alignment: .leading)
        .background(ColosseumTheme.surface)
        .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }

    private func scrollToFocused(using proxy: ScrollViewProxy) {
        guard let focusedKey else { return }
        proxy.scrollTo(focusedKey, anchor: .center)
    }
}
