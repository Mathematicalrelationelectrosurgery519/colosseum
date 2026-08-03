import SwiftData
import SwiftUI

struct BoardLibraryView: View {
    let boards: [Board]
    @Binding var search: String
    var onOpen: (Board) -> Void
    var onCreate: () -> Void
    var onImportArena: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: ColosseumTheme.gridGap)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Colosseum")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(ColosseumTheme.primaryText)
                        Text("Local boards for design curation")
                            .font(.system(size: 13))
                            .foregroundStyle(ColosseumTheme.secondaryText)
                    }
                    Spacer()
                    Button(action: onImportArena) {
                        Label("Are.na", systemImage: "arrow.down.left.and.arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                    Button(action: onCreate) {
                        Label("New Board", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .keyboardShortcut("n", modifiers: .command)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)

                if boards.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: ColosseumTheme.gridGap) {
                        ForEach(boards, id: \.id) { board in
                            Button {
                                onOpen(board)
                            } label: {
                                BoardCardView(board: board)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
                }
            }
        }
        .searchable(text: $search, prompt: "Search boards")
        .background(ColosseumTheme.canvas)
        .navigationTitle("")
        .toolbarBackground(ColosseumTheme.canvas, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No boards yet")
                .font(.title3)
                .foregroundStyle(ColosseumTheme.primaryText)
            Text("Create a board, or browse / import a public Are.na channel.")
                .font(.callout)
                .foregroundStyle(ColosseumTheme.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Are.na", action: onImportArena)
                    .buttonStyle(.bordered)
                Button("New Board", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }
}

struct BoardCardView: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Rectangle()
                    .fill(ColosseumTheme.surface)
                VStack(spacing: 6) {
                    Text(board.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ColosseumTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text("\(board.contentCount) blocks")
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.secondaryText)
                    Text(ColosseumFormatters.relativeDate(board.updatedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                    Text(ColosseumFormatters.byteCount(board.storageBytes))
                        .font(.system(size: 11))
                        .foregroundStyle(ColosseumTheme.tertiaryText)
                }
                .padding(16)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 1))

            Text(board.title)
                .font(.system(size: 12))
                .foregroundStyle(ColosseumTheme.secondaryText)
                .lineLimit(1)
        }
    }
}
