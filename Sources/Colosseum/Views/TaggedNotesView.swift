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
                .foregroundStyle(isSelected ? Color.black : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? color : color.opacity(0.14))
                .overlay(
                    Rectangle()
                        .stroke(color.opacity(isSelected ? 0 : 0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .animation(ColosseumMotion.soft, value: isSelected)
    }
}

struct TagMatchModeToggle: View {
    @Binding var mode: TagMatchMode

    var body: some View {
        HStack(spacing: 0) {
            modeButton(
                mode: .intersection,
                symbol: "∩",
                help: "Intersection — items with every selected tag"
            )
            Rectangle()
                .fill(ColosseumTheme.border)
                .frame(width: 1, height: 22)
            modeButton(
                mode: .union,
                symbol: "∪",
                help: "Union — items with any selected tag"
            )
        }
        .overlay(
            Rectangle()
                .stroke(ColosseumTheme.border, lineWidth: 1)
        )
    }

    private func modeButton(mode: TagMatchMode, symbol: String, help: String) -> some View {
        let selected = self.mode == mode
        return Button {
            self.mode = mode
        } label: {
            Text(symbol)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? ColosseumTheme.primaryText : ColosseumTheme.tertiaryText)
                .frame(width: 32, height: 26)
                .background(selected ? ColosseumTheme.elevated : Color.clear)
        }
        .buttonStyle(.plain)
        .help(help)
        .pointingHandCursor()
    }
}

struct TagFilterBar: View {
    let tags: [String]
    @Binding var selected: Set<String>
    @Binding var mode: TagMatchMode

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 12) {
                TagMatchModeToggle(mode: $mode)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            let key = TagParser.normalize(tag)
                            TagPill(tag: tag, isSelected: selected.contains(key)) {
                                if selected.contains(key) {
                                    selected.remove(key)
                                } else {
                                    selected.insert(key)
                                }
                            }
                        }
                    }
                }

                if !selected.isEmpty {
                    Button("Clear") {
                        selected.removeAll()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(ColosseumTheme.tertiaryText)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(ColosseumTheme.canvas)
        }
    }
}
