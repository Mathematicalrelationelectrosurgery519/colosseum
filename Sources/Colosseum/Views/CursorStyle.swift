import AppKit
import SwiftUI

extension View {
    /// Shows the pointing-hand cursor while the pointer is over this view.
    func pointingHandCursor(enabled: Bool = true) -> some View {
        onHover { hovering in
            guard enabled else { return }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
