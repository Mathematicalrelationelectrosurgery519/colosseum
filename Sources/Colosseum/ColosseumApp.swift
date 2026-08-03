import SwiftData
import SwiftUI

@main
struct ColosseumApp: App {
    private let container: ModelContainer

    init() {
        do {
            try MediaLibrary.ensureDirectories()
            let schema = Schema([Board.self, Block.self, Connection.self])
            let config = ModelConfiguration(
                "Colosseum",
                schema: schema,
                url: MediaLibrary.storeURL
            )
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to open Colosseum store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .background(WindowChromeStabilizer())
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Board") {
                    NotificationCenter.default.post(name: .colosseumNewBoard, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Add to Board…") {
                    NotificationCenter.default.post(name: .colosseumAdd, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Rename Board…") {
                    NotificationCenter.default.post(name: .colosseumRename, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Paste into Board") {
                    NotificationCenter.default.post(name: .colosseumPaste, object: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Open Files…") {
                    NotificationCenter.default.post(name: .colosseumOpenFiles, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Search Boards…") {
                    NotificationCenter.default.post(name: .colosseumSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Import…") {
                    NotificationCenter.default.post(name: .colosseumImportArena, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandGroup(after: .sidebar) {
                Button("Boards") {
                    NotificationCenter.default.post(name: .colosseumGoHome, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let colosseumNewBoard = Notification.Name("colosseum.newBoard")
    static let colosseumAdd = Notification.Name("colosseum.add")
    static let colosseumRename = Notification.Name("colosseum.rename")
    static let colosseumPaste = Notification.Name("colosseum.paste")
    static let colosseumOpenFiles = Notification.Name("colosseum.openFiles")
    static let colosseumImportArena = Notification.Name("colosseum.importArena")
    static let colosseumSearch = Notification.Name("colosseum.search")
    static let colosseumGoHome = Notification.Name("colosseum.goHome")
}
