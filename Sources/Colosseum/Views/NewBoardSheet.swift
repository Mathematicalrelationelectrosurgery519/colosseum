import SwiftUI

struct NewBoardSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onCreate: (String) -> Void

    @State private var title = ""
    @State private var keyMonitor = KeyNavMonitor()
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New board")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ColosseumTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ColosseumTheme.border).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField("Board title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(ColosseumTheme.surface)
                    .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
                    .focused($titleFocused)
                    .onSubmit { create() }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(ChromeButtonStyle())
                        .pointingHandCursor()
                    Button("Create") { create() }
                        .buttonStyle(ChromeButtonStyle(emphasized: true))
                        .pointingHandCursor()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(ColosseumTheme.canvas)
        .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))
        .transaction { transaction in transaction.animation = nil }
        .onAppear {
            installKeyMonitor()
            DispatchQueue.main.async { titleFocused = true }
        }
        .onDisappear { keyMonitor.remove() }
        .onExitCommand { dismiss() }
    }

    private func installKeyMonitor() {
        keyMonitor.onTab = {
            titleFocused = true
            return true
        }
        keyMonitor.onEscape = { dismiss() }
        keyMonitor.install()
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmed.isEmpty ? "Untitled" : trimmed)
        dismiss()
    }
}
