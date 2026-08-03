import SwiftData
import SwiftUI

struct BoardSearchView: View {
    let boards: [Board]
    var onSelect: (Board) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [Board] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return boards }
        return boards.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.notes.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ZStack {
            ColosseumTheme.canvas.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                    TextField("Search boards…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(ColosseumTheme.primaryText)
                        .focused($focused)
                        .onSubmit {
                            if let first = results.first {
                                onSelect(first)
                            }
                        }
                    ShortcutHint(text: "esc")
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(ChromeIconButtonStyle())
                    .pointingHandCursor()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ColosseumTheme.border)
                        .frame(height: 1)
                }

                if results.isEmpty {
                    Text(query.isEmpty ? "Type to filter boards" : "No boards match")
                        .font(.system(size: 13))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results, id: \.id) { board in
                                Button {
                                    onSelect(board)
                                } label: {
                                    HStack(spacing: 14) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(board.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(ColosseumTheme.primaryText)
                                            Text("\(board.contentCount) blocks · \(ColosseumFormatters.byteCount(board.storageBytes))")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ColosseumTheme.tertiaryText)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(ColosseumTheme.tertiaryText)
                                    }
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .background(ColosseumTheme.canvas)

                                Rectangle()
                                    .fill(ColosseumTheme.border.opacity(0.6))
                                    .frame(height: 0.5)
                                    .padding(.leading, 28)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 48)
        }
        .onAppear { focused = true }
        .onExitCommand(perform: onClose)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .transition(ColosseumMotion.overlayTransition)
    }
}
