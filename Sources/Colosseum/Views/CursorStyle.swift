import AppKit
import SwiftUI

extension View {
    /// Shows the pointing-hand cursor while the pointer is over this view.
    func pointingHandCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
