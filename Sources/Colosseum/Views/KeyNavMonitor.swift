import AppKit

/// Local key monitor that survives SwiftUI view value semantics.
@MainActor
final class KeyNavMonitor {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onEscape: (() -> Void)?
    /// When true, arrow keys are left alone (e.g. text caret movement).
    var shouldIgnoreArrows: (() -> Bool)?

    private var monitor: Any?

    func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Self.isEditingText {
                // Still allow Esc to dismiss even from text.
                if event.keyCode == 53 {
                    DispatchQueue.main.async { self.onEscape?() }
                    return nil
                }
                return event
            }
            if self.shouldIgnoreArrows?() == true {
                return event
            }
            switch event.keyCode {
            case 123:
                DispatchQueue.main.async { self.onLeft?() }
                return nil
            case 124:
                DispatchQueue.main.async { self.onRight?() }
                return nil
            case 53:
                DispatchQueue.main.async { self.onEscape?() }
                return nil
            default:
                return event
            }
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private static var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSText { return true }
        return false
    }
}
