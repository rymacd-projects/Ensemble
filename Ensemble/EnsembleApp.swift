import SwiftUI

@main
struct EnsembleApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerService()
    @StateObject private var uploader = UploadService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(uploader)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    library.saveNow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Music…") { library.showImporter = true }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
        }
    }
}
