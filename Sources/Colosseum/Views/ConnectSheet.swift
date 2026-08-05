import SwiftData
import SwiftUI

struct ConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Board.title) private var boards: [Board]

    let block: Block?
    let nestedBoard: Board?
    /// When set, selecting a board saves this remote Are.na item into it.
    var remoteItem: ArenaContentItem? = nil
    let excludeBoardID: UUID?

    @State private var search = ""
    @State private var mode = Mode.selection
    @State private var newBoardTitle = ""
    @State private var selectedBoardID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var keyMonitor = KeyNavMonitor()
    @FocusState private var overlayFocused: Bool
    @FocusState private var filterFocused: Bool
    @FocusState private var newBoardTitleFocused: Bool

    private enum Mode {
        case selection
        case create
    }

    private var availableBoards: [Board] {
        boards.filter { board in
            if let excludeBoardID, board.id == excludeBoardID { return false }
            if let nestedBoard, board.id == nestedBoard.id { return false }
            return true
        }
    }

    private var filtered: [Board] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableBoards }
        return availableBoards.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if mode == .selection {
                selectionView
            } else {
                createView
            }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(ColosseumTheme.canvas)
        .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
        .focusable()
        .focused($overlayFocused)
        .focusEffectDisabled()
        .transaction { transaction in transaction.animation = nil }
        .onAppear {
            selectedBoardID = filtered.first?.id
            overlayFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            keyMonitor.remove()
            if let block, block.connections.isEmpty {
                ImportService.deleteOrphanedBlockIfNeeded(block, context: context)
                try? context.save()
            }
        }
        .onChange(of: mode) { _, newMode in
            errorMessage = nil
            installKeyMonitor()
            DispatchQueue.main.async {
                if newMode == .create {
                    newBoardTitleFocused = true
                } else {
                    overlayFocused = true
                }
            }
        }
        .onChange(of: search) { _, _ in revalidateSelection() }
        .onChange(of: boards.map(\.id)) { _, _ in revalidateSelection() }
        .onExitCommand(perform: handleEscape)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(mode == .selection ? "Connect" : "New board")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ColosseumTheme.primaryText)
            Spacer()
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else if mode == .selection {
                Button("New") { showCreateView() }
                    .buttonStyle(ChromeButtonStyle())
                    .pointingHandCursor()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(ColosseumTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ColosseumTheme.border).frame(height: 1)
        }
    }

    private var selectionView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ColosseumTheme.tertiaryText)
                TextField("Filter boards", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .focused($filterFocused)
                    .disabled(isSaving)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(ColosseumTheme.surface)
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
            .padding(16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ColosseumTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Divider().overlay(ColosseumTheme.border)

            if filtered.isEmpty {
                Text("No boards available")
                    .font(.system(size: 13))
                    .foregroundStyle(ColosseumTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered, id: \.id) { board in
                                boardRow(board)
                                    .id(board.id)
                            }
                        }
                    }
                    .onChange(of: selectedBoardID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

        }
        .frame(height: 426)
    }

    private var createView: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Board title", text: $newBoardTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(ColosseumTheme.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(ColosseumTheme.surface)
                .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
                .focused($newBoardTitleFocused)
                .onSubmit { Task { await createAndConnect() } }
                .disabled(isSaving)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ColosseumTheme.secondaryText)
            }

            HStack {
                Spacer()
                Button("Cancel") { showSelectionView() }
                    .buttonStyle(ChromeButtonStyle())
                    .pointingHandCursor()
                    .disabled(isSaving)
                Button(isSaving ? "Creating…" : "Create & connect") {
                    Task { await createAndConnect() }
                }
                .buttonStyle(ChromeButtonStyle(emphasized: true))
                .pointingHandCursor()
                .disabled(isSaving)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func boardRow(_ board: Board) -> some View {
        let connected = isConnected(to: board)
        let selected = selectedBoardID == board.id
        return Button {
            selectedBoardID = board.id
            Task { await toggle(board) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(board.title.isEmpty ? "Untitled" : board.title)
                        .font(.system(size: 13))
                        .foregroundStyle(
                            connected ? ColosseumTheme.tertiaryText : ColosseumTheme.primaryText
                        )
                    Text("\(board.contentCount) blocks")
                        .font(.caption)
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                }
                Spacer()
                if connected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .pointingHandCursor()
        .overlay(alignment: .bottom) {
            Rectangle().fill(ColosseumTheme.border).frame(height: 0.5)
        }
    }

    private func installKeyMonitor() {
        keyMonitor.capturesNavigationWhileEditing = mode == .selection
        keyMonitor.onUp = { moveSelection(-1) }
        keyMonitor.onDown = { moveSelection(1) }
        keyMonitor.onEnter = { activateSelection() }
        keyMonitor.onTab = {
            guard mode == .selection else { return false }
            filterFocused = true
            return true
        }
        keyMonitor.onEscape = { handleEscape() }
        keyMonitor.onCharacter = { character in
            guard mode == .selection, character == "n" else { return false }
            DispatchQueue.main.async { showCreateView() }
            return true
        }
        keyMonitor.shouldIgnoreNavigation = { isSaving }
        keyMonitor.install()
    }

    private func moveSelection(_ delta: Int) {
        guard mode == .selection, !filtered.isEmpty, !isSaving else { return }
        let current = filtered.firstIndex(where: { $0.id == selectedBoardID })
        let next: Int
        if let current {
            next = max(0, min(filtered.count - 1, current + delta))
        } else {
            next = delta > 0 ? 0 : filtered.count - 1
        }
        selectedBoardID = filtered[next].id
        overlayFocused = true
    }

    private func activateSelection() {
        guard mode == .selection,
              let selectedBoardID,
              let board = filtered.first(where: { $0.id == selectedBoardID }),
              !isSaving
        else { return }
        Task { await toggle(board) }
    }

    private func revalidateSelection() {
        guard mode == .selection else { return }
        if let selectedBoardID, filtered.contains(where: { $0.id == selectedBoardID }) { return }
        selectedBoardID = filtered.first?.id
    }

    private func showCreateView() {
        guard !isSaving else { return }
        newBoardTitle = ""
        mode = .create
    }

    private func showSelectionView() {
        guard !isSaving else { return }
        newBoardTitle = ""
        mode = .selection
    }

    private func handleEscape() {
        guard !isSaving else { return }
        if mode == .create {
            showSelectionView()
        } else {
            dismiss()
        }
    }

    private func isConnected(to board: Board) -> Bool {
        matchingConnection(in: board) != nil
    }

    @MainActor
    private func createAndConnect() async {
        guard !isSaving else { return }
        let title = newBoardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = Board(title: title.isEmpty ? "Untitled" : title)
        context.insert(board)
        do {
            try await connectTarget(to: board)
            try context.save()
            isSaving = false
            newBoardTitle = ""
            selectedBoardID = board.id
            mode = .selection
        } catch {
            context.delete(board)
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    @MainActor
    private func toggle(_ board: Board) async {
        errorMessage = nil
        isSaving = true
        do {
            if let connection = matchingConnection(in: board) {
                ImportService.removeConnection(
                    connection,
                    deleteOrphanedBlock: block == nil,
                    context: context
                )
            } else {
                try await connectTarget(to: board)
            }
            try context.save()
            isSaving = false
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    @MainActor
    private func connectTarget(to board: Board) async throws {
        isSaving = true
        if let remoteItem {
            try await ArenaImportService.saveItem(remoteItem, into: board, context: context)
        } else if let block {
            ImportService.connect(block: block, to: board, context: context)
        } else if let nestedBoard {
            ImportService.connect(nestedBoard: nestedBoard, to: board, context: context)
        }
    }

    private func matchingConnection(in board: Board) -> Connection? {
        if let block {
            return board.connections.first { $0.block?.id == block.id }
        }
        if let nestedBoard {
            return board.connections.first { $0.nestedBoard?.id == nestedBoard.id }
        }
        guard let remoteItem else { return nil }
        return board.connections.first { connection in
            guard let existing = connection.block else { return false }
            if remoteItem.kind == .channel {
                return existing.kind == .arenaChannel
                    && existing.arenaSlug == remoteItem.channelSlug
            }
            if existing.arenaBlockID == remoteItem.id { return true }
            let remoteURLs = [
                remoteItem.sourceURL,
                remoteItem.imageURL,
                remoteItem.attachmentURL
            ].compactMap { $0 }
            return existing.sourceURL.map(remoteURLs.contains) == true
        }
    }
}
