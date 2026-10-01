import SwiftUI

@main
struct KeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = Library()

    var body: some Scene {
        Window("Keeper", id: "main") {
            RootView()
                .environment(library)
                .frame(minWidth: 860, minHeight: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 880)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.check() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Card or Folder…") { library.chooseFolder() }
                    .keyboardShortcut("o")
                if let card = library.newCard {
                    Button("Open \(card.name)") { library.open(card.root, name: card.name) }
                }
                Button("Close Folder") { library.close() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(library.phase == .empty)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Updater.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
