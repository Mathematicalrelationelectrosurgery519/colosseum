import AppKit

/// Local key monitor that survives SwiftUI view value semantics.
@MainActor
final class KeyNavMonitor {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onEnter: (() -> Void)?
    /// Return true to consume Tab.
    var onTab: (() -> Bool)?
    var onEscape: (() -> Void)?
    var onDelete: (() -> Void)?
    /// Control/Command+Z. Return true to consume.
    var onUndo: (() -> Bool)?
    /// Unmodified character keys (lowercase). Return true to consume the event.
    var onCharacter: ((String) -> Bool)?
    /// When true, arrow / enter keys are left alone (e.g. text caret movement).
    var shouldIgnoreNavigation: (() -> Bool)?

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
            if self.shouldIgnoreNavigation?() == true {
                if event.keyCode == 53 {
                    DispatchQueue.main.async { self.onEscape?() }
                    return nil
                }
                return event
            }
            switch event.keyCode {
            case 123: // left
                DispatchQueue.main.async { self.onLeft?() }
                return nil
            case 124: // right
                DispatchQueue.main.async { self.onRight?() }
                return nil
            case 126: // up
                if let onUp = self.onUp {
                    DispatchQueue.main.async { onUp() }
                    return nil
                }
                return event
            case 125: // down
                if let onDown = self.onDown {
                    DispatchQueue.main.async { onDown() }
                    return nil
                }
                return event
            case 36, 76: // return / keypad enter
                // Let ⌘↩ through for menu shortcuts (new board / add).
                if event.modifierFlags.contains(.command) { return event }
                if let onEnter = self.onEnter {
                    DispatchQueue.main.async { onEnter() }
                    return nil
                }
                return event
            case 48: // tab
                if event.modifierFlags.contains(.shift) { return event }
                if let onTab = self.onTab, onTab() {
                    return nil
                }
                return event
            case 51, 117: // delete / forward delete
                if let onDelete = self.onDelete {
                    DispatchQueue.main.async { onDelete() }
                    return nil
                }
                return event
            case 53: // escape
                DispatchQueue.main.async { self.onEscape?() }
                return nil
            default:
                let mods = event.modifierFlags.intersection([.command, .option, .control])
                if (mods.contains(.control) || mods.contains(.command)),
                   !mods.contains(.shift),
                   event.charactersIgnoringModifiers?.lowercased() == "z",
                   let onUndo = self.onUndo,
                   onUndo() {
                    return nil
                }
                if mods.isEmpty,
                   let chars = event.charactersIgnoringModifiers?.lowercased(),
                   chars.count == 1,
                   let onCharacter = self.onCharacter,
                   onCharacter(chars) {
                    return nil
                }
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
