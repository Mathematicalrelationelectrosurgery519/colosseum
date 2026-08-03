import AppKit
import SwiftUI

/// Plain, borderless notes field with live #tag coloring and ⌘-click to filter.
struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Add notes… Use #tags to group. ⌘-click a tag to filter."
    var onTagTap: (String) -> Void

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
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? TagAwareTextView else { return }
        textView.onTagTap = onTagTap
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            let max = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, max), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesEditor
        weak var textView: TagAwareTextView?
        private var applying = false

        init(_ parent: NotesEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !applying else { return }
            parent.text = textView.string
            applyHighlighting(to: textView)
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
