import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var apiKey = Keychain.get(NameGenerator.keyAccount) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Creative names")
                    .font(.headline)
                Text("Ensemble can ask Claude to invent a title for each song. Paste an Anthropic API key to turn that on. Without a key, Ensemble makes names offline.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                SecureField("Anthropic API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, newValue in
                        Keychain.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                     for: NameGenerator.keyAccount)
                    }
                Text("Stored in your Mac's Keychain. Only the file name, BPM and length are sent, never the audio.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Your library").font(.headline)
                Button("Show Ensemble's data folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.base])
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 320)
        .background(Theme.background)
    }
}
