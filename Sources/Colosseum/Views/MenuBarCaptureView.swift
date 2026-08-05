import AppKit
import SwiftData
import SwiftUI

struct MenuBarCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Board.updatedAt, order: .reverse) private var boards: [Board]

    @State private var phase: Phase = .idle
    @State private var inputText = ""
    @State private var notes = ""
    @State private var draft: CaptureDraft?
    @State private var selectedBoardIndex = 0
    @State private var selectedBoardID: UUID?
    @State private var successBoardTitle = ""
    @State private var errorMessage: String?
    @State private var keyMonitor = KeyNavMonitor()
    @State private var pasteMonitor: Any?
    @State private var panelWindow: NSWindow?

    @FocusState private var focus: FocusTarget?

    private enum FocusTarget: Hashable {
        case input
        case notes
    }

    private enum Phase: Equatable {
        case idle
        case resolving
        case selectBoard
        case notes
        case committing
        case success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPreview {
                previewHeader
                    .padding(12)
                Divider()
            }

            switch phase {
            case .idle, .resolving:
                idleBody
            case .selectBoard:
                boardSelectBody
            case .notes, .committing:
                notesBody
            case .success:
                successBody
            }
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            panelWindow = NSApp.keyWindow
            installKeys()
            installPasteMonitor()
            focusInput()
        }
        .onDisappear {
            keyMonitor.remove()
            removePasteMonitor()
            resetToIdle(clearError: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumRevealMainWindow)) { _ in
            openMainWindow()
        }
    }

    private var showsPreview: Bool {
        switch phase {
        case .selectBoard, .notes, .committing:
            return draft != nil
        default:
            return false
        }
    }

    // MARK: - Phase bodies

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Paste URL or media…", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .input)
                .onSubmit { Task { await resolveFromInput() } }
                .disabled(phase == .resolving)

            if phase == .resolving {
                Text("Resolving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
                .padding(.top, 2)

            menuButton("Open") {
                dismissPanel()
                openMainWindow()
            }

            menuButton("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(10)
    }

    private var boardSelectBody: some View {
        Group {
            if boards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No boards yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    menuButton("Open") {
                        dismissPanel()
                        openMainWindow()
                    }
                }
                .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                        boardRow(board, index: index)
                    }
                }
            }
        }
    }

    private var notesBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let board = selectedBoard {
                Text(board.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Notes (optional)", text: $notes)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .notes)
                .onSubmit { Task { await commitSelected() } }
                .disabled(phase == .committing)

            if phase == .committing {
                Text("Adding…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var successBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .medium))
            Text("Added to \(successBoardTitle)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Subviews

    private var selectedBoard: Board? {
        if let selectedBoardID {
            return boards.first(where: { $0.id == selectedBoardID })
        }
        guard boards.indices.contains(selectedBoardIndex) else { return nil }
        return boards[selectedBoardIndex]
    }

    @ViewBuilder
    private var previewHeader: some View {
        if let draft {
            HStack(alignment: .top, spacing: 12) {
                previewThumbnail(for: draft)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.kindLabel.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(draft.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                    if case .arenaChannel(let preview) = draft {
                        Text("\(preview.blockCount) blocks · \(preview.ownerName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func previewThumbnail(for draft: CaptureDraft) -> some View {
        if let image = draft.previewImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                Image(systemName: symbolName(for: draft.kind))
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func boardRow(_ board: Board, index: Int) -> some View {
        let selected = index == selectedBoardIndex
        return Button {
            selectedBoardIndex = index
            advanceToNotes()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    Text("\(board.contentCount) blocks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
            .foregroundStyle(selected ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func symbolName(for kind: BlockKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .link: return "link"
        case .text: return "text.alignleft"
        case .arenaChannel: return "square.grid.2x2"
        }
    }

    // MARK: - Window

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: {
                $0.canBecomeMain && $0.styleMask.contains(.closable)
            }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Keys & paste

    private func focusInput() {
        DispatchQueue.main.async {
            focus = .input
        }
    }

    private func focusNotes() {
        DispatchQueue.main.async {
            focus = .notes
        }
    }

    private func installKeys() {
        keyMonitor.onUp = {
            guard phase == .selectBoard, !boards.isEmpty else { return }
            selectedBoardIndex = max(0, selectedBoardIndex - 1)
        }
        keyMonitor.onDown = {
            guard phase == .selectBoard, !boards.isEmpty else { return }
            selectedBoardIndex = min(boards.count - 1, selectedBoardIndex + 1)
        }
        keyMonitor.onEnter = {
            switch phase {
            case .idle:
                Task { await resolveFromInput() }
            case .selectBoard:
                advanceToNotes()
            case .notes:
                Task { await commitSelected() }
            default:
                break
            }
        }
        keyMonitor.onTab = { false }
        keyMonitor.onEscape = {
            handleEscape()
        }
        keyMonitor.shouldIgnoreNavigation = {
            switch phase {
            case .idle, .selectBoard, .notes: return false
            default: return true
            }
        }
        keyMonitor.install()
    }

    private func handleEscape() {
        switch phase {
        case .selectBoard, .notes, .committing:
            resetToIdle(clearError: true)
            focusInput()
        default:
            dismissPanel()
        }
    }

    private func dismissPanel() {
        resetToIdle(clearError: true)
        let window = panelWindow ?? NSApp.keyWindow
        DispatchQueue.main.async {
            window?.orderOut(nil)
        }
    }

    /// Intercept ⌘V while the panel is open so the app's "Paste into Board" menu
    /// shortcut doesn't steal it from the capture fields.
    private func installPasteMonitor() {
        removePasteMonitor()
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let isPaste = flags == .command
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isPaste else { return event }

            switch phase {
            case .idle, .resolving:
                Task { await handleIdlePaste() }
                return nil
            case .notes:
                if let string = NSPasteboard.general.string(forType: .string) {
                    notes = string
                }
                return nil
            case .selectBoard, .committing, .success:
                return nil
            }
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }

    /// Prefer URL/text into the field; auto-resolve true media pastes (images/files).
    private func pasteboardHasNonTextMedia() -> Bool {
        let pb = NSPasteboard.general

        if let string = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           string.hasPrefix("http://") || string.hasPrefix("https://") {
            return false
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: { !$0.isFileURL }) {
            return false
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: \.isFileURL) {
            return true
        }
        if pb.availableType(from: [.png, .tiff, .init("com.compuserve.gif")]) != nil {
            return true
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty {
            return true
        }
        return false
    }

    private func handleIdlePaste() async {
        if pasteboardHasNonTextMedia() {
            await resolveFromPasteboard()
            return
        }

        let pb = NSPasteboard.general
        if let string = pb.string(forType: .string) {
            inputText = string
            focus = .input
            return
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first(where: { !$0.isFileURL }) {
            inputText = url.absoluteString
            focus = .input
            return
        }

        await resolveFromPasteboard()
    }

    // MARK: - Capture

    private func resolveFromInput() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await resolveFromPasteboard()
            return
        }
        phase = .resolving
        errorMessage = nil
        do {
            let resolved = try await ImportService.resolveURLString(trimmed)
            present(draft: resolved)
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            focusInput()
        }
    }

    private func resolveFromPasteboard() async {
        phase = .resolving
        errorMessage = nil
        do {
            let resolved = try await ImportService.resolvePasteboard()
            switch resolved {
            case .remote, .arenaChannel:
                break
            default:
                inputText = ""
            }
            present(draft: resolved)
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            focusInput()
        }
    }

    private func present(draft: CaptureDraft) {
        self.draft = draft
        notes = ""
        selectedBoardIndex = 0
        selectedBoardID = nil
        errorMessage = nil
        phase = .selectBoard
        focus = nil
        // Resign the text field so arrow/enter are handled by KeyNavMonitor.
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func advanceToNotes() {
        guard phase == .selectBoard,
              boards.indices.contains(selectedBoardIndex)
        else { return }
        selectedBoardID = boards[selectedBoardIndex].id
        notes = ""
        errorMessage = nil
        phase = .notes
        focusNotes()
    }

    private func commitSelected() async {
        guard phase == .notes,
              let draft,
              let board = selectedBoard
        else { return }

        phase = .committing
        errorMessage = nil
        do {
            try await ImportService.commit(draft, notes: notes, into: board, context: context)
            try context.save()
            successBoardTitle = board.title
            phase = .success
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismissPanel()
        } catch {
            phase = .notes
            errorMessage = error.localizedDescription
            focusNotes()
        }
    }

    private func resetToIdle(clearError: Bool) {
        phase = .idle
        draft = nil
        notes = ""
        inputText = ""
        selectedBoardIndex = 0
        selectedBoardID = nil
        successBoardTitle = ""
        if clearError { errorMessage = nil }
    }
}
