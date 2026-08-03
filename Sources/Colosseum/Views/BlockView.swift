import AppKit
import AVKit
import SwiftData
import SwiftUI

struct BlockView: View {
    let board: Board
    let connections: [Connection]
    @Binding var selectedID: UUID?
    var onClose: () -> Void

    @Environment(\.modelContext) private var context

    @State private var showConnect = false
    @State private var sidebarTab: SidebarTab = .connections
    @State private var player: AVPlayer?
    @FocusState private var focused: Bool

    enum SidebarTab: String, CaseIterable {
        case connections = "Connections"
        case notes = "Notes"
    }

    private var index: Int {
        connections.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    private var connection: Connection? {
        guard index >= 0, index < connections.count else { return nil }
        return connections[index]
    }

    private var block: Block? { connection?.block }

    var body: some View {
        HStack(spacing: 0) {
            mediaPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(ColosseumTheme.border)

            sidebar
                .frame(width: ColosseumTheme.sidebarWidth)
        }
        .background(ColosseumTheme.canvas)
        .focusable()
        .focused($focused)
        .onAppear {
            focused = true
            reloadPlayer()
        }
        .onChange(of: selectedID) { _, _ in
            reloadPlayer()
        }
        .onExitCommand(perform: onClose)
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-1)
            case .right: step(1)
            default: break
            }
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
                    if let player {
                        VideoPlayer(player: player)
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

                        TextField(
                            block.notes.isEmpty ? "No description." : "Description",
                            text: Binding(
                                get: { block.notes },
                                set: { block.notes = $0 }
                            ),
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(ColosseumTheme.secondaryText)
                        .lineLimit(3...8)

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

                        Picker("", selection: $sidebarTab) {
                            ForEach(SidebarTab.allCases, id: \.self) { tab in
                                if tab == .connections {
                                    Text("Connections \(block.connections.count)").tag(tab)
                                } else {
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 8)

                        switch sidebarTab {
                        case .connections:
                            connectionsList(for: block)
                        case .notes:
                            if block.kind == .text {
                                TextEditor(text: Binding(
                                    get: { block.textBody },
                                    set: { block.textBody = $0 }
                                ))
                                .frame(minHeight: 160)
                                .scrollContentBackground(.hidden)
                                .background(ColosseumTheme.surface)
                            } else {
                                TextEditor(text: Binding(
                                    get: { block.notes },
                                    set: { block.notes = $0 }
                                ))
                                .frame(minHeight: 160)
                                .scrollContentBackground(.hidden)
                                .background(ColosseumTheme.surface)
                            }
                        }
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
            Text("Your connections")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ColosseumTheme.secondaryText)

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
        let next = index + delta
        guard next >= 0, next < connections.count else { return }
        selectedID = connections[next].id
    }

    private func reloadPlayer() {
        player?.pause()
        player = nil
        guard let block, block.kind == .video, let path = block.localRelativePath else { return }
        let url = MediaLibrary.absoluteURL(relativePath: path)
        player = AVPlayer(url: url)
    }
}
