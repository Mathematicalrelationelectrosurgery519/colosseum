import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BoardOverviewView: View {
    @Bindable var board: Board
    @Binding var path: [UUID]

    @Environment(\.modelContext) private var context

    @State private var selectedConnectionID: UUID?
    @State private var showAddSheet = false
    @State private var showRename = false
    @State private var renameTitle = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: ColosseumTheme.cellMin, maximum: 260), spacing: ColosseumTheme.gridGap)]

    private var connections: [Connection] {
        board.sortedConnections
    }

    private var selectedConnection: Connection? {
        connections.first(where: { $0.id == selectedConnectionID })
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: ColosseumTheme.gridGap) {
                    Button {
                        showAddSheet = true
                    } label: {
                        AddBlockCell()
                    }
                    .buttonStyle(.plain)

                    ForEach(connections, id: \.id) { connection in
                        connectionCell(connection)
                    }
                }
                .padding(28)
            }
            .background(ColosseumTheme.canvas)

            if let connection = selectedConnection, connection.block != nil {
                BlockView(
                    board: board,
                    connections: connections.filter { $0.block != nil },
                    selectedID: $selectedConnectionID,
                    onClose: { selectedConnectionID = nil }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .navigationTitle(board.title)
        .toolbar {
            ToolbarItemGroup {
                if isImporting {
                    ProgressView().controlSize(.small)
                }
                Button("Add") { showAddSheet = true }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Rename") {
                    renameTitle = board.title
                    showRename = true
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddContentSheet(board: board)
        }
        .alert("Rename Board", isPresented: $showRename) {
            TextField("Title", text: $renameTitle)
            Button("Save") {
                board.title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? board.title : renameTitle
                board.updatedAt = .now
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onDrop(of: [.fileURL, .url, .plainText, .image, .png, .tiff], isTargeted: $isTargeted) { providers in
            _ = handleDrop(providers)
            return true
        }
        .overlay {
            if isTargeted {
                Rectangle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumAdd)) { _ in
            showAddSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumPaste)) { _ in
            Task { await paste() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .colosseumOpenFiles)) { _ in
            openFiles()
        }
        .alert("Import Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func connectionCell(_ connection: Connection) -> some View {
        if let nested = connection.nestedBoard {
            Button {
                path.append(nested.id)
            } label: {
                NestedBoardCell(board: nested)
            }
            .buttonStyle(.plain)
            .contextMenu { connectionMenu(connection) }
        } else if let block = connection.block {
            Button {
                selectedConnectionID = connection.id
            } label: {
                switch block.kind {
                case .image, .video:
                    MediaBlockCell(block: block)
                case .text:
                    TextBlockCell(block: block)
                case .link:
                    LinkBlockCell(block: block)
                case .arenaChannel:
                    ArenaBlockCell(block: block)
                }
            }
            .buttonStyle(.plain)
            .contextMenu { connectionMenu(connection) }
        }
    }

    @ViewBuilder
    private func connectionMenu(_ connection: Connection) -> some View {
        if let block = connection.block, block.kind == .arenaChannel,
           let urlString = block.arenaURL ?? block.sourceURL,
           let url = URL(string: urlString) {
            Button("Open on Are.na") { NSWorkspace.shared.open(url) }
        }
        if let nested = connection.nestedBoard {
            Button("Open Board") { path.append(nested.id) }
        }
        Divider()
        Button("Remove from Board", role: .destructive) {
            ImportService.removeConnection(connection, deleteOrphanedBlock: true, context: context)
            try? context.save()
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .mpeg4Movie, .quickTimeMovie, .png, .jpeg, .gif, .webP, .heic]
        guard panel.runModal() == .OK else { return }
        Task { await importURLs(panel.urls) }
    }

    private func paste() async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await ImportService.importPasteboard(into: board, context: context)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importURLs(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await ImportService.importFiles(urls, into: board, context: context)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            isImporting = true
            defer { isImporting = false }
            do {
                var fileURLs: [URL] = []
                var strings: [String] = []

                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        if let url = try await loadFileURL(from: provider) {
                            fileURLs.append(url)
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        if let url = try await loadURL(from: provider) {
                            if url.isFileURL {
                                fileURLs.append(url)
                            } else {
                                strings.append(url.absoluteString)
                            }
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        if let text = try await loadString(from: provider) {
                            strings.append(text)
                        }
                    } else if provider.canLoadObject(ofClass: NSImage.self) {
                        let image = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NSImage, Error>) in
                            _ = provider.loadObject(ofClass: NSImage.self) { object, error in
                                if let error { cont.resume(throwing: error); return }
                                guard let image = object as? NSImage else {
                                    cont.resume(throwing: ImportService.ImportError.failed("Invalid image"))
                                    return
                                }
                                cont.resume(returning: image)
                            }
                        }
                        try await importImage(image)
                    }
                }

                if !fileURLs.isEmpty {
                    try await ImportService.importFiles(fileURLs, into: board, context: context)
                }
                for string in strings {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                        try await ImportService.importURLString(trimmed, into: board, context: context)
                    } else if !trimmed.isEmpty {
                        ImportService.addTextBlock(trimmed, title: "", into: board, context: context)
                    }
                }
                try context.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    private func importImage(_ image: NSImage) async throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { throw ImportService.ImportError.failed("Could not read image") }

        let blockID = UUID()
        let dest = try MediaLibrary.writeData(data, into: blockID, filename: "drop.png")
        let (w, h) = ThumbnailService.imageDimensions(at: dest)
        let thumb = try ThumbnailService.generateImageThumbnail(from: dest, blockID: blockID)
        let block = Block(
            id: blockID,
            kind: .image,
            title: "Dropped image",
            localRelativePath: MediaLibrary.relativePath(from: dest),
            thumbRelativePath: thumb.map { MediaLibrary.relativePath(from: $0) },
            mimeType: "image/png",
            byteSize: Int64(data.count),
            width: w,
            height: h
        )
        context.insert(block)
        ImportService.connect(block: block, to: board, context: context)
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error { cont.resume(throwing: error); return }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else if let url = item as? URL {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error { cont.resume(throwing: error); return }
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadString(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error { cont.resume(throwing: error); return }
                if let string = item as? String {
                    cont.resume(returning: string)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    cont.resume(returning: string)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
