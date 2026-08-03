import SwiftData
import SwiftUI

struct BoardLibraryView: View {
    let boards: [Board]
    var showsToolbar = true
    var onOpen: (Board) -> Void
    var onCreate: () -> Void
    var onImportArena: () -> Void
    var onSearch: () -> Void

    @State private var gridFocusID: UUID?
    @State private var gridWidth: CGFloat = 900
    @State private var keyMonitor = KeyNavMonitor()
    @FocusState private var homeFocused: Bool

    private let minCardWidth: CGFloat = 200

    private var columnCount: Int {
        let inner = max(minCardWidth, gridWidth - 56)
        return max(1, Int((inner + ColosseumTheme.gridGap) / (minCardWidth + ColosseumTheme.gridGap)))
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minCardWidth, maximum: 280), spacing: ColosseumTheme.gridGap)]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if boards.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: ColosseumTheme.gridGap) {
                            ForEach(boards, id: \.id) { board in
                                Button {
                                    gridFocusID = board.id
                                    onOpen(board)
                                } label: {
                                    BoardCardView(board: board)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                                .id(board.id)
                                .overlay {
                                    if board.id == gridFocusID, showsToolbar {
                                        Rectangle()
                                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                                            .padding(.bottom, 22)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: HomeGridWidthKey.self, value: geo.size.width)
                            }
                        )
                    }
                }
            }
            .onPreferenceChange(HomeGridWidthKey.self) { gridWidth = $0 }
            .onChange(of: gridFocusID) { _, id in
                guard let id, showsToolbar else { return }
                withAnimation(ColosseumMotion.soft) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .background(ColosseumTheme.canvas)
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(ColosseumTheme.canvas, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .toolbar {
            if showsToolbar {
                ColosseumHomeShortcutHintsToolbar()
            }
        }
        .focusable()
        .focused($homeFocused)
        .focusEffectDisabled()
        .onAppear { syncHomeKeyboard() }
        .onDisappear { keyMonitor.remove() }
        .onChange(of: showsToolbar) { _, _ in syncHomeKeyboard() }
        .onChange(of: boards.map(\.id)) { _, ids in
            if let gridFocusID, !ids.contains(gridFocusID) {
                self.gridFocusID = ids.first
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No boards yet")
                .font(.title3)
                .foregroundStyle(ColosseumTheme.primaryText)
            Text("Create a board with ⌘↩, or import with ⌘I.")
                .font(.callout)
                .foregroundStyle(ColosseumTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    private func syncHomeKeyboard() {
        guard showsToolbar else {
            keyMonitor.remove()
            return
        }
        homeFocused = true
        keyMonitor.onLeft = { moveFocus(delta: -1) }
        keyMonitor.onRight = { moveFocus(delta: 1) }
        keyMonitor.onUp = { moveFocus(delta: -columnCount) }
        keyMonitor.onDown = { moveFocus(delta: columnCount) }
        keyMonitor.onEnter = { openFocused() }
        keyMonitor.onEscape = nil
        keyMonitor.shouldIgnoreNavigation = { !showsToolbar }
        keyMonitor.install()
        DispatchQueue.main.async {
            homeFocused = true
            if gridFocusID == nil {
                gridFocusID = boards.first?.id
            }
        }
    }

    private func moveFocus(delta: Int) {
        guard showsToolbar, !boards.isEmpty else { return }
        homeFocused = true
        if let idx = boards.firstIndex(where: { $0.id == gridFocusID }) {
            let next = idx + delta
            guard next >= 0, next < boards.count else { return }
            withAnimation(ColosseumMotion.soft) {
                gridFocusID = boards[next].id
            }
        } else {
            withAnimation(ColosseumMotion.soft) {
                gridFocusID = boards[0].id
            }
        }
    }

    private func openFocused() {
        guard showsToolbar else { return }
        let board = boards.first(where: { $0.id == gridFocusID }) ?? boards.first
        guard let board else { return }
        gridFocusID = board.id
        onOpen(board)
    }
}

private struct HomeGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
