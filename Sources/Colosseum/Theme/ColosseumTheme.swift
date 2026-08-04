import SwiftUI

enum ColosseumTheme {
    static let canvas = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let elevated = Color(red: 0.14, green: 0.14, blue: 0.14)
    static let border = Color.white.opacity(0.12)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
    /// Titles for remote / Are.na boards.
    static let remoteBoardTitle = Color(red: 1.0, green: 0.70, blue: 0.42)
    static let gridGap: CGFloat = 16
    static let cellMin: CGFloat = 180
    static let sidebarWidth: CGFloat = 320
    /// Empty space between a cell's inner border and the focus selection ring.
    static let selectionRingGap: CGFloat = 3
    static let selectionRingWidth: CGFloat = 2
    /// Tag-colored cell borders (plain / untagged stay thinner).
    static let taggedBorderWidth: CGFloat = 3
}

/// A segment in a board / remote breadcrumb path.
struct BoardPathSegment: Identifiable, Hashable {
    let id: String
    let title: String
}

extension View {
    func colosseumCanvas() -> some View {
        self.background(ColosseumTheme.canvas.ignoresSafeArea())
    }
}
