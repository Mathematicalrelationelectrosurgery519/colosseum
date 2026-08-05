import SwiftData
import SwiftUI

struct ImportArenaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var onImported: (Board) -> Void
    var onBrowse: (ArenaBrowseTarget) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case importBoard = "Import"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .browse
    @State private var urlText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var progressLabel = ""
    @State private var progressValue: Double = 0
    @State private var progressTotal: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Are.na")
                    .font(.title3.weight(.medium))
                Spacer()
                Button("Close") { dismiss() }
                    .disabled(isWorking)
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(isWorking)

            Text(mode == .browse
                  ? "Preview a public channel in Colosseum — media streams from Are.na and connected blocks remain remote."
                  : "Download the whole channel into a new local board (images, video, and audio copied to disk).")
                .font(.callout)
                .foregroundStyle(ColosseumTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://www.are.na/user/channel-slug", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)

            if isWorking {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progressTotal > 0 ? progressValue : nil, total: progressTotal > 0 ? progressTotal : 1)
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(ColosseumTheme.secondaryText)
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
                    .disabled(isWorking)
                Button(primaryLabel) {
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
        .frame(width: 500)
        .background(ColosseumTheme.canvas)
    }

    private var primaryLabel: String {
        switch mode {
        case .browse: return "Browse Channel"
        case .importBoard: return isWorking ? "Importing…" : "Import Board"
        }
    }

    private var canSubmit: Bool {
        ArenaService.isArenaChannelURL(urlText)
    }

    private func submit() async {
        errorMessage = nil
        switch mode {
        case .browse:
            guard let parsed = ArenaService.parseChannelURL(urlText) else {
                errorMessage = "Enter a valid Are.na channel URL"
                return
            }
            let target = ArenaBrowseTarget(
                slug: parsed.channelSlug,
                urlString: urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
            onBrowse(target)
        case .importBoard:
            await importBoard()
        }
    }

    private func importBoard() async {
        isWorking = true
        progressLabel = "Starting…"
        progressValue = 0
        progressTotal = 0
        defer { isWorking = false }

        do {
            let board = try await ArenaImportService.importChannel(
                fromURLString: urlText,
                context: context
            ) { progress in
                progressLabel = progress.phase
                progressValue = Double(progress.completed)
                progressTotal = Double(max(progress.total, 0))
            }
            onImported(board)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
