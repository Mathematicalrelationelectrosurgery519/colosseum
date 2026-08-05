import AppKit

/// Local key monitor that survives SwiftUI view value semantics.
@MainActor
final class KeyNavMonitor {
    private final class WeakMonitor {
        weak var value: KeyNavMonitor?

        init(_ value: KeyNavMonitor) {
            self.value = value
        }
    }

    private static var monitorStacks: [ObjectIdentifier: [WeakMonitor]] = [:]

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
    /// Command+C. Return true to consume.
    var onCopy: (() -> Bool)?
    /// Unmodified character keys (lowercase). Return true to consume the event.
    var onCharacter: ((String) -> Bool)?
    /// Allow a focused text field to keep typing while this monitor owns arrows/enter.
    var capturesNavigationWhileEditing = false
    /// When true, arrow / enter keys are left alone (e.g. text caret movement).
    var shouldIgnoreNavigation: (() -> Bool)?

    private var monitor: Any?
    private weak var ownerWindow: NSWindow?
    private var ownerWindowID: ObjectIdentifier?

    func install() {
        remove()
        ownerWindow = NSApp.keyWindow
        if let ownerWindow {
            let id = ObjectIdentifier(ownerWindow)
            ownerWindowID = id
            var stack = Self.monitorStacks[id, default: []]
            stack.removeAll { $0.value == nil || $0.value === self }
            stack.append(WeakMonitor(self))
            Self.monitorStacks[id] = stack
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.owns(event) else { return event }
            if event.keyCode == 48,
               !event.modifierFlags.contains(.shift),
               let onTab = self.onTab,
               onTab() {
                return nil
            }
            if Self.isEditingText, !self.capturesNavigationWhileEditing {
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
                if mods == [.command],
                   event.charactersIgnoringModifiers?.lowercased() == "c",
                   let onCopy = self.onCopy,
                   onCopy() {
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
        unregisterOwner()
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// True when an AppKit text field/view has keyboard focus (caret movement should win).
    static var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSText { return true }
        return false
    }

    private func owns(_ event: NSEvent) -> Bool {
        guard let ownerWindow, let ownerWindowID else { return true }
        let eventWindow = event.window ?? NSApp.keyWindow
        guard eventWindow === ownerWindow else { return false }

        var stack = Self.monitorStacks[ownerWindowID] ?? []
        stack.removeAll { $0.value == nil }
        Self.monitorStacks[ownerWindowID] = stack.isEmpty ? nil : stack
        return stack.last?.value === self
    }

    private func unregisterOwner() {
        guard let ownerWindowID else {
            ownerWindow = nil
            return
        }
        var stack = Self.monitorStacks[ownerWindowID] ?? []
        stack.removeAll { $0.value == nil || $0.value === self }
        Self.monitorStacks[ownerWindowID] = stack.isEmpty ? nil : stack
        self.ownerWindowID = nil
        ownerWindow = nil
    }
}
