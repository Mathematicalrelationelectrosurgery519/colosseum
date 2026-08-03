import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            revealMainWindow()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                self?.handleWindowBecameKey(window)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                self?.handleWindowWillClose(window)
            }
        }
    }

    func revealMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .colosseumRevealMainWindow, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleWindowBecameKey(_ window: NSWindow) {
        guard isMainWindow(window) else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func handleWindowWillClose(_ window: NSWindow) {
        guard isMainWindow(window) else { return }
        // The closing window is still in NSApp.windows / may still report isVisible
        // during willClose — exclude it so we actually retire to the menu bar.
        DispatchQueue.main.async { [weak self] in
            self?.retireToMenuBarIfNeeded(excluding: window)
        }
    }

    private func retireToMenuBarIfNeeded(excluding closingWindow: NSWindow? = nil) {
        let hasVisibleMain = NSApp.windows.contains { window in
            guard window !== closingWindow else { return false }
            return isMainWindow(window) && window.isVisible
        }
        guard !hasVisibleMain else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        // Exclude status-item panels and other non-app chrome.
        guard window.styleMask.contains(.titled) else { return false }
        guard window.styleMask.contains(.closable) else { return false }
        guard !window.className.contains("StatusBar") else { return false }
        return true
    }
}
