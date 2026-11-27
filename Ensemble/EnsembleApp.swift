import SwiftUI

@main
struct EnsembleApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerService()
    @StateObject private var uploader = UploadService()
    @StateObject private var themes = ThemeStore.shared
    @StateObject private var columns = ColumnLayout()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(uploader)
                .environmentObject(themes)
                .environmentObject(columns)
                .frame(minWidth: 900, minHeight: 600)
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
            CommandMenu("Theme") {
                Picker("Theme", selection: $themes.selectedID) {
                    ForEach(Palette.blues) { Text($0.name).tag($0.id) }
                    Divider()
                    ForEach(Palette.reds) { Text($0.name).tag($0.id) }
                    Divider()
                    ForEach(Palette.greens) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
        }
    }
}
