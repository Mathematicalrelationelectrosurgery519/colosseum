import SwiftData
import SwiftUI

struct AddContentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Board.title) private var allBoards: [Board]

    let board: Board

    @State private var urlText = ""
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var selectedNestedBoardID: UUID?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var tab: Tab = .url

    enum Tab: String, CaseIterable, Identifiable {
        case url = "URL"
        case note = "Note"
        case board = "Board"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add")
                    .font(.title3.weight(.medium))
                Spacer()
                Button("Close") { dismiss() }
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Group {
                switch tab {
                case .url:
                    TextField("https://… or are.na channel URL", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                    Text("Pastes images/videos when possible. Are.na channel URLs add a preview card (import a full board from the library).")
                        .font(.caption)
                        .foregroundStyle(ColosseumTheme.secondaryText)
                case .note:
                    TextField("Title (optional)", text: $noteTitle)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $noteBody)
                        .font(.body)
                        .frame(minHeight: 140)
                        .overlay(Rectangle().stroke(ColosseumTheme.border))
                case .board:
                    Picker("Connect board", selection: $selectedNestedBoardID) {
                        Text("Select…").tag(Optional<UUID>.none)
                        ForEach(connectableBoards, id: \.id) { b in
                            Text(b.title).tag(Optional(b.id))
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isWorking ? "Working…" : "Add") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || !canSubmit)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(ColosseumTheme.canvas)
    }

    private var connectableBoards: [Board] {
        allBoards.filter { other in
            other.id != board.id &&
            !board.connections.contains(where: { $0.nestedBoard?.id == other.id })
        }
    }

    private var canSubmit: Bool {
        switch tab {
        case .url: return !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .note: return !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .board: return selectedNestedBoardID != nil
        }
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            switch tab {
            case .url:
                try await ImportService.importURLString(urlText, into: board, context: context)
            case .note:
                ImportService.addTextBlock(noteBody, title: noteTitle, into: board, context: context)
            case .board:
                guard let id = selectedNestedBoardID,
                      let nested = allBoards.first(where: { $0.id == id })
                else { return }
                ImportService.connect(nestedBoard: nested, to: board, context: context)
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
