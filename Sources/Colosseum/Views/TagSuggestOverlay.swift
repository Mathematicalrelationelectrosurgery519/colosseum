import AppKit
import SwiftUI

/// Compact caret-anchored tag autocomplete panel (AppKit, matches TagAssignPopover chrome).
final class TagSuggestOverlay {
    enum Item: Equatable {
        case tag(String)
        case createNew

        var title: String {
            switch self {
            case .tag(let tag): return TagParser.displayLabel(tag)
            case .createNew: return "create new"
            }
        }
    }

    private var panel: NSPanel?
    private var table: SuggestTable?
    private(set) var items: [Item] = []
    private(set) var selectedIndex = 0
    private var escapeMonitor: Any?
    var onSelect: ((Item) -> Void)?
    var onDismiss: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(items: [Item], selectedIndex: Int, screenPoint: NSPoint) {
        self.items = items
        self.selectedIndex = min(max(0, selectedIndex), max(items.count - 1, 0))
        ensurePanel()
        table?.reload(items: items, selectedIndex: self.selectedIndex)
        layout(at: screenPoint)
        panel?.orderFront(nil)
        installEscapeMonitor()
    }

    func update(items: [Item], selectedIndex: Int, screenPoint: NSPoint) {
        guard isVisible else {
            show(items: items, selectedIndex: selectedIndex, screenPoint: screenPoint)
            return
        }
        self.items = items
        self.selectedIndex = min(max(0, selectedIndex), max(items.count - 1, 0))
        table?.reload(items: items, selectedIndex: self.selectedIndex)
        layout(at: screenPoint)
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = (selectedIndex + delta + items.count) % items.count
        selectedIndex = next
        table?.setSelectedIndex(next)
    }

    func acceptSelection() {
        guard items.indices.contains(selectedIndex) else {
            hide()
            return
        }
        let item = items[selectedIndex]
        hide()
        onSelect?(item)
    }

    func hide() {
        removeEscapeMonitor()
        panel?.orderOut(nil)
        items = []
        selectedIndex = 0
    }

    private func ensurePanel() {
        if panel != nil { return }

        let table = SuggestTable()
        table.onActivate = { [weak self] index in
            guard let self, self.items.indices.contains(index) else { return }
            self.selectedIndex = index
            self.acceptSelection()
        }
        table.onHover = { [weak self] index in
            guard let self else { return }
            self.selectedIndex = index
            self.table?.setSelectedIndex(index)
        }
        self.table = table

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = table
        self.panel = panel
    }

    private func layout(at screenPoint: NSPoint) {
        guard let panel, let table else { return }
        let size = table.fittingSizeForItems(count: max(items.count, 1))
        // screenPoint is caret baseline; place panel just below.
        var origin = NSPoint(
            x: screenPoint.x,
            y: screenPoint.y - size.height - 6
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })
            ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.x + size.width > visible.maxX {
                origin.x = visible.maxX - size.width - 4
            }
            if origin.x < visible.minX {
                origin.x = visible.minX + 4
            }
            if origin.y < visible.minY {
                origin.y = screenPoint.y + 4
            }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.keyCode == 53 else { return event }
            self.hide()
            self.onDismiss?()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }
}

// MARK: - Table

private final class SuggestTable: NSView {
    var onActivate: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?

    private var items: [TagSuggestOverlay.Item] = []
    private var selectedIndex = 0
    private var rowButtons: [SuggestRowButton] = []

    private let rowHeight: CGFloat = 28
    private let hPad: CGFloat = 10
    private let vPad: CGFloat = 6
    private let width: CGFloat = 168

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(ColosseumTheme.surface).cgColor
        layer?.borderColor = NSColor(ColosseumTheme.border).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fittingSizeForItems(count: Int) -> CGSize {
        let rows = max(count, 1)
        return CGSize(
            width: width,
            height: vPad * 2 + CGFloat(rows) * rowHeight
        )
    }

    func reload(items: [TagSuggestOverlay.Item], selectedIndex: Int) {
        self.items = items
        self.selectedIndex = selectedIndex
        rowButtons.forEach { $0.removeFromSuperview() }
        rowButtons = []

        for (index, item) in items.enumerated() {
            let button = SuggestRowButton(item: item)
            button.target = self
            button.action = #selector(rowClicked(_:))
            button.tag = index
            button.isSelectedRow = index == selectedIndex
            addSubview(button)
            rowButtons.append(button)
        }
        needsLayout = true
    }

    func setSelectedIndex(_ index: Int) {
        selectedIndex = index
        for (i, button) in rowButtons.enumerated() {
            button.isSelectedRow = i == index
        }
    }

    override func layout() {
        super.layout()
        var y = bounds.maxY - vPad - rowHeight
        for button in rowButtons {
            button.frame = NSRect(
                x: hPad,
                y: y,
                width: bounds.width - hPad * 2,
                height: rowHeight
            )
            y -= rowHeight
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = rowButtons.firstIndex(where: { $0.frame.contains(point) }) {
            onHover?(index)
        }
    }

    @objc private func rowClicked(_ sender: NSButton) {
        onActivate?(sender.tag)
    }
}

private final class SuggestRowButton: NSButton {
    var isSelectedRow = false {
        didSet { needsDisplay = true }
    }

    private let item: TagSuggestOverlay.Item

    init(item: TagSuggestOverlay.Item) {
        self.item = item
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        title = ""
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedRow {
            NSColor.white.withAlphaComponent(0.08).setFill()
            dirtyRect.insetBy(dx: -4, dy: 1).fill()
        }

        let title = item.title as NSString
        let color: NSColor
        switch item {
        case .tag(let tag):
            color = isSelectedRow ? TagColor.nsColor(for: tag) : NSColor(ColosseumTheme.secondaryText)
        case .createNew:
            color = NSColor(ColosseumTheme.tertiaryText)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isSelectedRow ? .medium : .regular),
            .foregroundColor: color
        ]
        let size = title.size(withAttributes: attrs)
        let origin = CGPoint(
            x: 6,
            y: (bounds.height - size.height) / 2
        )
        title.draw(at: origin, withAttributes: attrs)
    }
}
