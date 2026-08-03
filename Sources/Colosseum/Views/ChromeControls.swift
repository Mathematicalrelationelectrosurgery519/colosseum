import AppKit
import SwiftUI

enum ChromeMetrics {
    static let controlHeight: CGFloat = 30
    static let iconButtonWidth: CGFloat = 30
    static let homeIconSize: CGFloat = 22
    static let boardColumnsMin = 2
    static let boardColumnsMax = 8
    static let boardColumnsDefault = 4
    /// Magnification delta required to move one column step (higher = less sensitive).
    static let pinchStepThreshold: CGFloat = 0.22
    /// Match board grid content inset so trailing toolbar controls line up.
    static let contentInset: CGFloat = 28
}

/// Bordered chrome control matching the home Import button look.
struct ChromeButtonStyle: ButtonStyle {
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(emphasized ? Color.black : ColosseumTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: ChromeMetrics.controlHeight)
            .background(emphasized ? Color.white : ColosseumTheme.surface)
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ChromeIconButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? ColosseumTheme.primaryText : ColosseumTheme.secondaryText)
            .frame(width: ChromeMetrics.iconButtonWidth, height: ChromeMetrics.controlHeight)
            .background(active ? ColosseumTheme.elevated : ColosseumTheme.surface)
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ShortcutHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(ColosseumTheme.tertiaryText)
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func colosseumPlainToolbarItem() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct WindowContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(ColosseumTheme.canvas, for: .window)
        } else {
            content
        }
    }
}

/// Keeps window titlebar/toolbar chrome identical across board transitions.
struct WindowChromeStabilizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(to: nsView.window) }
    }

    private static func apply(to window: NSWindow?) {
        guard let window else { return }
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        if #available(macOS 15.0, *) {
            window.isMovableByWindowBackground = true
        }
    }
}

struct ColosseumLeadingToolbar: ToolbarContent {
    var onHome: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            AppHomeButton {
                onHome?()
            }
        }
        .colosseumPlainToolbarItem()
    }
}

struct ColosseumHomeActionsToolbar: ToolbarContent {
    var onSearch: () -> Void
    var onImport: () -> Void
    var onCreate: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(ChromeIconButtonStyle())
                .help("Search boards (⌘K)")
                .pointingHandCursor()

                Button(action: onImport) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(ChromeButtonStyle())
                .pointingHandCursor()

                Button(action: onCreate) {
                    Label("New Board", systemImage: "plus")
                }
                .buttonStyle(ChromeButtonStyle(emphasized: true))
                .pointingHandCursor()
            }
            .padding(.trailing, max(0, ChromeMetrics.contentInset - 10))
        }
        .colosseumPlainToolbarItem()
    }
}

struct ColosseumBoardHeaderToolbar: ToolbarContent {
    let title: String
    var onHome: () -> Void
    var onTitleTap: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 0) {
                AppHomeButton(action: onHome)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTitleTap)
                    .pointingHandCursor()
                    .help("Back to board overview")

                HStack(spacing: 10) {
                    ShortcutHint(text: "⌘+")
                    ShortcutHint(text: "⌘R")
                }
                .padding(.leading, 14)
                .allowsHitTesting(false)
            }
        }
        .colosseumPlainToolbarItem()
    }
}

struct ColumnDensityControl: View {
    @Binding var columnCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ColosseumTheme.tertiaryText)

            Slider(
                value: Binding(
                    get: { Double(columnCount) },
                    set: { columnCount = Int($0.rounded()) }
                ),
                in: Double(ChromeMetrics.boardColumnsMin)...Double(ChromeMetrics.boardColumnsMax),
                step: 1
            )
            .controlSize(.mini)
            .tint(Color.white.opacity(0.45))
            .frame(width: 88)

            Text("\(columnCount)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(ColosseumTheme.tertiaryText)
                .frame(width: 12, alignment: .trailing)
        }
        .help("Items per column")
    }
}

struct ColosseumColumnSliderToolbar: ToolbarContent {
    @Binding var columnCount: Int
    var isImporting = false
    var visible = true

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 10) {
                if isImporting {
                    ProgressView().controlSize(.small)
                }
                ColumnDensityControl(columnCount: $columnCount)
                    .opacity(visible ? 1 : 0)
                    .allowsHitTesting(visible)
                    .animation(ColosseumMotion.overlay, value: visible)
            }
            // System toolbar already insets a bit; pad the rest to match grid content (28).
            .padding(.trailing, max(0, ChromeMetrics.contentInset - 10))
        }
        .colosseumPlainToolbarItem()
    }
}

struct AppHomeButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let image = Bundle.module.image(forResource: "AppIconMark") {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ColosseumTheme.primaryText)
                }
            }
            .frame(width: ChromeMetrics.homeIconSize, height: ChromeMetrics.homeIconSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Boards")
        .pointingHandCursor()
    }
}
