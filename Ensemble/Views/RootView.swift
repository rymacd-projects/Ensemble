import SwiftUI
import UniformTypeIdentifiers

enum Destination: Hashable {
    case library
    case playlist(UUID)
    case upload
    case samples
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var themes: ThemeStore
    @State private var destination: Destination = .library

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(destination: $destination)
                    .frame(width: 232)
                Rectangle().fill(Theme.hairline).frame(width: 1)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            PlayerBar()
        }
        .id(themes.selectedID)   // redraw everything in the new colors
        .background(Theme.background)
        .onAppear {
            // Lets the background updater close Ensemble safely (it saves first).
            QuitSignal.install { library.saveNow() }
        }
        .fileImporter(isPresented: $library.showImporter,
                      allowedContentTypes: [.audio, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await library.importFiles(urls) }
            }
        }
        .alert("Ensemble", isPresented: Binding(get: { library.message != nil },
                                                 set: { if !$0 { library.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.message ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .library:
            LibraryView(playlistID: nil)
        case .playlist(let id):
            LibraryView(playlistID: id).id(id)
        case .upload:
            UploadView()
        case .samples:
            SamplesView()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var destination: Destination
    @EnvironmentObject private var library: LibraryStore

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""
    @State private var dropTarget: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text("Ensemble")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gradient)
            }
            .padding(.top, 38)
            .padding(.horizontal, 18)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                navRow("Your Music", icon: "music.note.house.fill", target: .library)
                navRow("Upload", icon: "arrow.up.forward.app.fill", target: .upload)
                navRow("Sample Finder", icon: "waveform.badge.magnifyingglass", target: .samples)
            }
            .padding(.horizontal, 10)

            HStack {
                Text("PLAYLISTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    newPlaylistName = ""
                    showNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.cyan)
                .help("New playlist")
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(library.playlists) { playlist in
                        playlistRow(playlist)
                    }
                    if library.playlists.isEmpty {
                        Text("Create a playlist with +, then drag songs onto it.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
        }
        .background(Theme.sidebar)
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                let playlist = library.createPlaylist(named: newPlaylistName)
                destination = .playlist(playlist.id)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: Binding(get: { renaming != nil },
                                                        set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let renaming { library.renamePlaylist(renaming.id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func navRow(_ title: String, icon: String, target: Destination) -> some View {
        let selected = destination == target
        return Button { destination = target } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(selected ? Theme.cyan : Theme.textSecondary)
                Text(title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.blue.opacity(0.22) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        let target = Destination.playlist(playlist.id)
        let selected = destination == target
        let hovering = dropTarget == playlist.id
        return Button { destination = target } label: {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .frame(width: 22)
                    .foregroundStyle(selected ? Theme.cyan : Theme.textSecondary)
                Text(playlist.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                Text("\(playlist.songIDs.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Theme.cyan.opacity(0.28) : (selected ? Theme.blue.opacity(0.22) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { dropTarget == playlist.id },
            set: { dropTarget = $0 ? playlist.id : (dropTarget == playlist.id ? nil : dropTarget) }
        )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String, let songID = UUID(uuidString: text) else { return }
                Task { @MainActor in library.add(songID, toPlaylist: playlist.id) }
            }
            return true
        }
        .contextMenu {
            Button("Rename…") {
                renameText = playlist.name
                renaming = playlist
            }
            Button("Delete Playlist", role: .destructive) {
                if destination == target { destination = .library }
                library.deletePlaylist(playlist.id)
            }
        }
    }
}
