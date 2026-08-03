import SwiftUI

enum ColosseumMotion {
    static let soft = Animation.easeOut(duration: 0.10)
    static let standard = Animation.easeOut(duration: 0.12)
    static let overlay = Animation.easeOut(duration: 0.14)

    static var overlayTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.992)),
            removal: .opacity
        )
    }

    static var itemTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }

    static var fade: AnyTransition { .opacity }
}
