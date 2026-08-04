import AppKit
import SwiftUI

/// Plain, borderless notes field with live #tag coloring, autocomplete, and ⌘-click to filter.
struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "notes..."
    /// Popularity-ranked board tags for `#` autocomplete.
    var suggestionTags: [String] = []
    var onTagTap: (String) -> Void
    /// Increment to force the field to become first responder (e.g. Tab in block preview).
    var focusNonce: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = TagAwareTextView()
        textView.delegate = context.coordinator
        textView.onTagTap = onTagTap
        textView.placeholderString = placeholder
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor(ColosseumTheme.secondaryText)
        textView.insertionPointColor = NSColor.white
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text
        context.coordinator.applyHighlighting(to: textView)

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.configureSuggest(for: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? TagAwareTextView else { return }
        textView.onTagTap = onTagTap
        textView.placeholderString = placeholder
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            let max = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, max), length: 0))
        }
        if focusNonce != context.coordinator.lastFocusNonce {
            context.coordinator.lastFocusNonce = focusNonce
            DispatchQueue.main.async {
                scroll.window?.makeFirstResponder(textView)
            }
        }
        textView.needsDisplay = true
        context.coordinator.refreshSuggestions()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesEditor
        weak var textView: TagAwareTextView?
        private var applying = false
        var lastFocusNonce = 0
        let suggest = TagSuggestOverlay()
        /// Keep selection stable across filter updates when the same query family continues.
        private var lastQuery: String?

        init(_ parent: NotesEditor) {
            self.parent = parent
        }

        func configureSuggest(for textView: TagAwareTextView) {
            suggest.onSelect = { [weak self] item in
                self?.accept(item)
            }
            textView.onSuggestCommand = { [weak self] command in
                self?.handleSuggestCommand(command) ?? false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !applying else { return }
            parent.text = textView.string
            applyHighlighting(to: textView)
            textView.needsDisplay = true
            refreshSuggestions()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !applying else { return }
            refreshSuggestions()
        }

        func textDidEndEditing(_ notification: Notification) {
            suggest.hide()
            lastQuery = nil
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            handleSuggestCommand(commandSelector)
        }

        private func handleSuggestCommand(_ commandSelector: Selector) -> Bool {
            guard suggest.isVisible else { return false }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                suggest.moveSelection(-1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                suggest.moveSelection(1)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertTab(_:)) {
                suggest.acceptSelection()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                suggest.hide()
                lastQuery = nil
                return true
            }
            return false
        }

        func refreshSuggestions() {
            guard let textView else {
                suggest.hide()
                return
            }
            guard textView.window?.firstResponder === textView else {
                suggest.hide()
                lastQuery = nil
                return
            }

            let selected = textView.selectedRange()
            guard selected.length == 0,
                  let edit = TagParser.activeTagEdit(in: textView.string, caret: selected.location)
            else {
                suggest.hide()
                lastQuery = nil
                return
            }

            let matches = TagParser.autocomplete(
                query: edit.query,
                from: parent.suggestionTags,
                limit: 3
            )

            let items: [TagSuggestOverlay.Item]
            if matches.isEmpty {
                // Bare `#` with no board tags yet — nothing useful to show.
                if edit.query.isEmpty {
                    suggest.hide()
                    lastQuery = nil
                    return
                }
                items = [.createNew]
            } else {
                items = matches.map { .tag($0) }
            }

            let selectedIndex: Int
            if lastQuery == edit.query, suggest.isVisible {
                selectedIndex = min(suggest.selectedIndex, items.count - 1)
            } else {
                selectedIndex = 0
            }
            lastQuery = edit.query

            let caretRange = NSRange(location: selected.location, length: 0)
            var rect = textView.firstRect(forCharacterRange: caretRange, actualRange: nil)
            if rect == .zero {
                // Fallback: bottom-left of text view in screen space.
                let local = NSPoint(x: 0, y: textView.bounds.minY)
                let windowPoint = textView.convert(local, to: nil)
                rect = textView.window?.convertToScreen(NSRect(origin: windowPoint, size: .zero)) ?? .zero
            }
            // Prefer the lower-left of the caret glyph box.
            let point = NSPoint(x: rect.minX, y: rect.minY)
            suggest.update(items: items, selectedIndex: selectedIndex, screenPoint: point)
        }

        private func accept(_ item: TagSuggestOverlay.Item) {
            guard let textView else { return }
            let selected = textView.selectedRange()
            guard let edit = TagParser.activeTagEdit(in: textView.string, caret: selected.location)
            else { return }

            switch item {
            case .createNew:
                // Typed token already in the buffer — just dismiss.
                lastQuery = nil
                return
            case .tag(let tag):
                // Trailing space ends the token so the popup doesn't reopen on the filled tag.
                let replacement = TagParser.displayLabel(tag) + " "
                if textView.shouldChangeText(in: edit.range, replacementString: replacement) {
                    textView.replaceCharacters(in: edit.range, with: replacement)
                    textView.didChangeText()
                    let caret = edit.range.location + (replacement as NSString).length
                    textView.setSelectedRange(NSRange(location: caret, length: 0))
                }
                lastQuery = nil
                suggest.hide()
                applyHighlighting(to: textView)
                parent.text = textView.string
            }
        }

        func applyHighlighting(to textView: NSTextView) {
            applying = true
            defer { applying = false }

            let storage = textView.textStorage
            let full = NSRange(location: 0, length: storage?.length ?? 0)
            let selected = textView.selectedRange()

            storage?.beginEditing()
            storage?.setAttributes([
                .foregroundColor: NSColor(ColosseumTheme.secondaryText),
                .font: NSFont.systemFont(ofSize: 13)
            ], range: full)

            let pattern = try! NSRegularExpression(
                pattern: #"(?<![\w/])#([A-Za-z0-9][A-Za-z0-9_-]*)"#,
                options: []
            )
            let matches = pattern.matches(in: textView.string, options: [], range: full)
            var tagRanges: [(NSRange, String)] = []
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let tagRange = match.range(at: 1)
                let tag = (textView.string as NSString).substring(with: tagRange)
                let color = TagColor.nsColor(for: tag)
                storage?.addAttributes([
                    .foregroundColor: color,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: color.withAlphaComponent(0.35),
                    .cursor: NSCursor.pointingHand
                ], range: match.range)
                tagRanges.append((match.range, tag))
            }
            storage?.endEditing()

            if let tagView = textView as? TagAwareTextView {
                tagView.tagRanges = tagRanges
            }
            textView.setSelectedRange(selected)
        }
    }
}

final class TagAwareTextView: NSTextView {
    var onTagTap: ((String) -> Void)?
    var tagRanges: [(NSRange, String)] = []
    var placeholderString: String = "notes..."
    /// Return true when a suggest overlay consumed the command.
    var onSuggestCommand: ((Selector) -> Bool)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(ColosseumTheme.tertiaryText),
            .font: font ?? .systemFont(ofSize: 13)
        ]
        let origin = CGPoint(
            x: textContainerOrigin.x + textContainerInset.width,
            y: textContainerOrigin.y + textContainerInset.height
        )
        (placeholderString as NSString).draw(at: origin, withAttributes: attrs)
    }

    override func doCommand(by selector: Selector) {
        if onSuggestCommand?(selector) == true { return }
        super.doCommand(by: selector)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if tag(at: event) != nil {
            NSCursor.pointingHand.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if tag(at: event) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let tag = tag(at: event) {
            onTagTap?(tag)
            return
        }
        super.mouseDown(with: event)
    }

    private func tag(at event: NSEvent) -> String? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        for (range, tag) in tagRanges where NSLocationInRange(index, range) {
            return tag
        }
        return nil
    }
}
