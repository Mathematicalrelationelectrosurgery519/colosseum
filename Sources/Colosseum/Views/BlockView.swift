import AppKit
import AVFoundation
import SwiftData
import SwiftUI

struct BlockView: View {
    let board: Board
    let connections: [Connection]
    @Binding var selectedID: UUID?
    var onClose: () -> Void
    var onTagTap: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var context

    @State private var showConnect = false
    @State private var loopingPlayer: LoopingVideoPlayer?
    @State private var keyMonitor = KeyNavMonitor()
    @FocusState private var focused: Bool

    private var index: Int {
        guard let selectedID else { return 0 }
        return connections.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    private var connection: Connection? {
        guard !connections.isEmpty, index >= 0, index < connections.count else { return nil }
        return connections[index]
    }

    private var block: Block? { connection?.block }

    var body: some View {
        HStack(spacing: 0) {
            mediaPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }

            Divider().overlay(ColosseumTheme.border)

            sidebar
                .frame(width: ColosseumTheme.sidebarWidth)
        }
        .background(ColosseumTheme.canvas)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            reloadPlayer()
            keyMonitor.onLeft = { step(-1) }
            keyMonitor.onRight = { step(1) }
            keyMonitor.onEscape = onClose
            keyMonitor.install()
        }
        .onDisappear {
            keyMonitor.remove()
            loopingPlayer?.stop()
            loopingPlayer = nil
        }
        .onChange(of: selectedID) { _, _ in
            focused = true
            reloadPlayer()
        }
        .onExitCommand(perform: onClose)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-1)
            case .right: step(1)
            default: break
            }
        }
        .background {
            HStack {
                Button("", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("", action: { step(-1) })
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("", action: { step(1) })
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showConnect) {
            if let block {
                ConnectSheet(block: block, nestedBoard: nil, excludeBoardID: nil)
            }
        }
    }

    @ViewBuilder
    private var mediaPane: some View {
        ZStack {
            ColosseumTheme.canvas
            if let block {
                mediaContent(for: block)
                    .id(block.id)
                    .transition(ColosseumMotion.fade)
            }
        }
        .animation(ColosseumMotion.standard, value: selectedID)
    }

    @ViewBuilder
    private func mediaContent(for block: Block) -> some View {
        switch block.kind {
        case .image:
            if let path = block.localRelativePath {
                let url = MediaLibrary.absoluteURL(relativePath: path)
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                }
            }
        case .video:
            if let loopingPlayer {
                PlayerView(player: loopingPlayer.player)
                    .padding(24)
            }
        case .text:
            ScrollView {
                Text(block.textBody)
                    .font(.system(size: 18))
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(40)
            }
        case .link:
            VStack(spacing: 16) {
                Image(systemName: "link")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(ColosseumTheme.secondaryText)
                Text(block.displayTitle)
                    .font(.title2)
                    .foregroundStyle(ColosseumTheme.primaryText)
                    .multilineTextAlignment(.center)
                if let source = block.sourceURL, let url = URL(string: source) {
                    Button("Open Link") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                }
            }
            .padding(40)
        case .arenaChannel:
            VStack(spacing: 12) {
                Text(block.title)
                    .font(.title)
                    .foregroundStyle(ColosseumTheme.primaryText)
                if let owner = block.arenaOwnerName {
                    Text("by \(owner)")
                        .foregroundStyle(ColosseumTheme.secondaryText)
                }
                Text("\(block.arenaBlockCount) blocks")
                    .foregroundStyle(ColosseumTheme.secondaryText)
                if let urlString = block.arenaURL ?? block.sourceURL,
                   let url = URL(string: urlString) {
                    Button("Open on Are.na") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Spacer()
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(index <= 0)

                Button { step(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(index >= connections.count - 1)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("w", modifiers: .command)
            }
            .foregroundStyle(ColosseumTheme.secondaryText)
            .padding(16)

            if let block {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Title", text: Binding(
                            get: { block.title },
                            set: {
                                block.title = $0
                                board.updatedAt = .now
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ColosseumTheme.primaryText)

                        notesSection(for: block)

                        if block.kind == .text {
                            TextEditor(text: Binding(
                                get: { block.textBody },
                                set: { block.textBody = $0 }
                            ))
                            .font(.system(size: 13))
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(ColosseumTheme.surface)
                            .overlay(Rectangle().stroke(ColosseumTheme.border, lineWidth: 0.5))
                        }

                        metaTable(for: block)

                        HStack(spacing: 8) {
                            Button("Connect →") { showConnect = true }
                                .buttonStyle(.borderedProminent)
                                .tint(.white)
                                .foregroundStyle(.black)

                            Menu("Actions") {
                                if let path = block.localRelativePath {
                                    let url = MediaLibrary.absoluteURL(relativePath: path)
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    Button("Open File") { NSWorkspace.shared.open(url) }
                                }
                                if let source = block.sourceURL, let url = URL(string: source) {
                                    Button("Open Source URL") { NSWorkspace.shared.open(url) }
                                }
                                if block.kind == .arenaChannel,
                                   let urlString = block.arenaURL ?? block.sourceURL,
                                   let url = URL(string: urlString) {
                                    Button("Open on Are.na") { NSWorkspace.shared.open(url) }
                                }
                                Divider()
                                Button("Remove from Board", role: .destructive) {
                                    if let connection {
                                        ImportService.removeConnection(
                                            connection,
                                            deleteOrphanedBlock: true,
                                            context: context
                                        )
                                        try? context.save()
                                        onClose()
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                        }

                        Text("Connections \(block.connections.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ColosseumTheme.secondaryText)
                            .padding(.top, 8)

                        connectionsList(for: block)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }

            Spacer(minLength: 0)
        }
        .background(ColosseumTheme.canvas)
    }

    @ViewBuilder
    private func notesSection(for block: Block) -> some View {
        NotesEditor(
            text: Binding(
                get: { block.notes },
                set: {
                    block.notes = $0
                    board.updatedAt = .now
                }
            ),
            onTagTap: onTagTap
        )
        .frame(minHeight: 64, maxHeight: 140)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func metaTable(for block: Block) -> some View {
        VStack(spacing: 0) {
            metaRow("Added", ColosseumFormatters.relativeDate(block.createdAt))
            metaRow("Content Type", block.contentTypeLabel)
            if block.byteSize > 0 {
                metaRow("File Size", ColosseumFormatters.byteCount(block.byteSize))
            }
            if block.width > 0, block.height > 0 {
                metaRow("Dimensions", "\(block.width) × \(block.height)")
            }
            if block.kind == .video, block.duration > 0 {
                metaRow("Duration", ColosseumFormatters.duration(block.duration))
            }
            if block.kind == .arenaChannel {
                metaRow("Blocks", "\(block.arenaBlockCount)")
                if let owner = block.arenaOwnerName {
                    metaRow("By", owner)
                }
            }
            if let source = block.sourceURL, !source.isEmpty {
                metaRow("Source", source)
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(ColosseumTheme.tertiaryText)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(ColosseumTheme.primaryText)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ColosseumTheme.border)
                .frame(height: 0.5)
        }
    }

    private func connectionsList(for block: Block) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(block.connections.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { conn in
                if let parent = conn.board {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parent.title)
                                .foregroundStyle(ColosseumTheme.primaryText)
                            Text("\(parent.contentCount) · \(ColosseumFormatters.relativeDate(conn.createdAt))")
                                .font(.caption)
                                .foregroundStyle(ColosseumTheme.tertiaryText)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            if block.connections.isEmpty {
                Text("Not connected to any boards.")
                    .font(.caption)
                    .foregroundStyle(ColosseumTheme.tertiaryText)
            }
        }
        .padding(.top, 4)
    }

    private func step(_ delta: Int) {
        guard !connections.isEmpty else { return }
        let next = index + delta
        guard next >= 0, next < connections.count else { return }
        withAnimation(ColosseumMotion.standard) {
            selectedID = connections[next].id
        }
        focused = true
    }

    private func reloadPlayer() {
        loopingPlayer?.stop()
        loopingPlayer = nil
        guard let block, block.kind == .video, let path = block.localRelativePath else { return }
        let url = MediaLibrary.absoluteURL(relativePath: path)
        let next = VideoPlayback.looping(url: url, muted: false)
        loopingPlayer = next
        next.play()
    }
}
