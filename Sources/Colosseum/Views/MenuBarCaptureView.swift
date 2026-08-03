import AppKit
import SwiftData
import SwiftUI

struct MenuBarCaptureView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Board.updatedAt, order: .reverse) private var boards: [Board]

    @State private var phase: Phase = .idle
    @State private var inputText = ""
    @State private var notes = ""
    @State private var draft: CaptureDraft?
    @State private var selectedBoardIndex = 0
    @State private var successBoardTitle = ""
    @State private var errorMessage: String?
    @State private var keyMonitor = KeyNavMonitor()
    @State private var pasteMonitor: Any?

    @FocusState private var focus: FocusTarget?

    private enum FocusTarget: Hashable {
        case input
        case notes
    }

    private enum Phase: Equatable {
        case idle
        case resolving
        case confirm
        case committing
        case success
    }

    var body: some View {
        Group {
            switch phase {
            case .idle, .resolving:
                idlePhase
            case .confirm, .committing:
                confirmPhase
            case .success:
                successPhase
            }
        }
        .frame(width: 360, height: 420)
        .background(ColosseumTheme.canvas)
        .preferredColorScheme(.dark)
        .onAppear {
            installKeys()
            installPasteMonitor()
            focusInput()
        }
        .onDisappear {
            keyMonitor.remove()
            removePasteMonitor()
            resetToIdle(clearError: true)
        }
    }

    // MARK: - Phases

    private var idlePhase: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capture")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ColosseumTheme.primaryText)

            TextField("Paste URL or media…", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(ColosseumTheme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(ColosseumTheme.surface)
                .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
                .focused($focus, equals: .input)
                .onSubmit { Task { await resolveFromInput() } }
                .disabled(phase == .resolving)

            HStack(spacing: 8) {
                ShortcutHint(text: "⌘V")
                Text("paste")
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
                ShortcutHint(text: "↩")
                Text(phase == .resolving ? "resolving…" : "preview")
                    .font(.system(size: 11))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
                Spacer()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(16)
        .onPasteCommand(of: [.url, .plainText, .png, .tiff, .jpeg, .fileURL]) { _ in
            Task { await resolveFromPasteboard() }
        }
    }

    private var confirmPhase: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewHeader
                .padding(16)

            Divider().overlay(ColosseumTheme.border)

            if boards.isEmpty {
                Text("No boards yet")
                    .font(.system(size: 12))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                                boardRow(board, index: index)
                                    .id(board.id)
                            }
                        }
                    }
                    .onChange(of: selectedBoardIndex) { _, newValue in
                        guard boards.indices.contains(newValue) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(boards[newValue].id, anchor: .center)
                        }
                    }
                }
            }

            Divider().overlay(ColosseumTheme.border)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Notes (optional)", text: $notes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ColosseumTheme.surface)
                    .overlay(Rectangle().stroke(
                        focus == .notes ? ColosseumTheme.primaryText.opacity(0.35) : ColosseumTheme.border,
                        lineWidth: 1
                    ))
                    .focused($focus, equals: .notes)
                    .onSubmit { Task { await commitSelected() } }
                    .disabled(phase == .committing)

                HStack(spacing: 8) {
                    ShortcutHint(text: "↑↓")
                    Text("board")
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                    ShortcutHint(text: "⇥")
                    Text("notes")
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                    ShortcutHint(text: "↩")
                    Text(phase == .committing ? "adding…" : "add")
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                    Spacer()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    private var successPhase: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ColosseumTheme.primaryText)
            Text("Added to \(successBoardTitle)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ColosseumTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewHeader: some View {
        if let draft {
            HStack(alignment: .top, spacing: 12) {
                previewThumbnail(for: draft)
                    .frame(width: 72, height: 72)
                    .clipped()
                    .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.kindLabel.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                    Text(draft.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ColosseumTheme.primaryText)
                        .lineLimit(3)
                    if case .arenaChannel(let preview) = draft {
                        Text("\(preview.blockCount) blocks · \(preview.ownerName)")
                            .font(.system(size: 11))
                            .foregroundStyle(ColosseumTheme.secondaryText)
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
                ColosseumTheme.surface
                Image(systemName: symbolName(for: draft.kind))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
            }
        }
    }

    private func boardRow(_ board: Board, index: Int) -> some View {
        let selected = index == selectedBoardIndex && focus != .notes
        return Button {
            selectedBoardIndex = index
            focus = nil
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.title)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .foregroundStyle(ColosseumTheme.primaryText)
                        .lineLimit(1)
                    Text("\(board.contentCount) blocks")
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                }
                Spacer()
                if selected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selected ? ColosseumTheme.elevated : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func symbolName(for kind: BlockKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .link: return "link"
        case .text: return "text.alignleft"
        case .arenaChannel: return "square.grid.2x2"
        }
    }

    // MARK: - Actions

    private func focusInput() {
        DispatchQueue.main.async {
            focus = .input
        }
    }

    private func installKeys() {
        keyMonitor.onUp = {
            guard phase == .confirm, focus != .notes, !boards.isEmpty else { return }
            selectedBoardIndex = max(0, selectedBoardIndex - 1)
        }
        keyMonitor.onDown = {
            guard phase == .confirm, focus != .notes, !boards.isEmpty else { return }
            selectedBoardIndex = min(boards.count - 1, selectedBoardIndex + 1)
        }
        keyMonitor.onEnter = {
            switch phase {
            case .idle:
                Task { await resolveFromInput() }
            case .confirm:
                Task { await commitSelected() }
            default:
                break
            }
        }
        keyMonitor.onTab = {
            guard phase == .confirm else { return false }
            focus = .notes
            return true
        }
        keyMonitor.onEscape = {
            switch phase {
            case .confirm, .resolving:
                resetToIdle(clearError: true)
                focusInput()
            case .idle, .success, .committing:
                resetToIdle(clearError: true)
            }
        }
        keyMonitor.shouldIgnoreNavigation = {
            phase != .confirm && phase != .idle
        }
        keyMonitor.install()
    }

    private func installPasteMonitor() {
        removePasteMonitor()
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isPaste = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isPaste, phase == .idle || phase == .resolving else { return event }
            if pasteboardHasNonTextMedia() {
                Task { await resolveFromPasteboard() }
                return nil
            }
            return event
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }

    private func pasteboardHasNonTextMedia() -> Bool {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: { $0.isFileURL }) {
            return true
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty,
           pb.string(forType: .string) == nil {
            return true
        }
        // Image data without a string URL.
        if pb.availableType(from: [.png, .tiff]) != nil,
           pb.string(forType: .string)?.hasPrefix("http") != true {
            return true
        }
        return false
    }

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
            // Keep typed URL in field if pasteboard mirrored it; otherwise clear for media.
            if case .remote = resolved { /* keep */ }
            else if case .arenaChannel = resolved { /* keep */ }
            else { inputText = "" }
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
        errorMessage = nil
        phase = .confirm
        focus = nil
    }

    private func commitSelected() async {
        guard phase == .confirm,
              let draft,
              boards.indices.contains(selectedBoardIndex)
        else { return }

        let board = boards[selectedBoardIndex]
        phase = .committing
        errorMessage = nil
        do {
            try await ImportService.commit(draft, notes: notes, into: board, context: context)
            try context.save()
            successBoardTitle = board.title
            phase = .success
            try? await Task.sleep(nanoseconds: 500_000_000)
            resetToIdle(clearError: true)
            focusInput()
        } catch {
            phase = .confirm
            errorMessage = error.localizedDescription
        }
    }

    private func resetToIdle(clearError: Bool) {
        phase = .idle
        draft = nil
        notes = ""
        inputText = ""
        selectedBoardIndex = 0
        successBoardTitle = ""
        if clearError { errorMessage = nil }
    }
}
