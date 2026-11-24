import SwiftUI
import UniformTypeIdentifiers

/// Column widths shared by the header and every row so they line up.
enum Col {
    static let art: CGFloat = 52
    static let bpm: CGFloat = 64
    static let time: CGFloat = 64
    static let date: CGFloat = 108
}

struct LibraryView: View {
    let playlistID: UUID?

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerService

    enum SortKey { case manual, creative, original, bpm, duration, added }

    @State private var sortKey: SortKey = .manual
    @State private var ascending = true
    @State private var search = ""
    @State private var selection: UUID?
    @State private var dropTargeted = false
    @State private var songToDelete: Song?

    private var playlist: Playlist? {
        guard let playlistID else { return nil }
        return library.playlists.first { $0.id == playlistID }
    }

    private var baseSongs: [Song] {
        if let playlist { return library.songs(in: playlist) }
        return library.songs
    }

    private var shown: [Song] {
        var list = baseSongs
        if !search.isEmpty {
            list = list.filter { song in
                [song.creativeName, song.originalName, song.notes]
                    .contains { $0.localizedCaseInsensitiveContains(search) }
            }
        }
        func before(_ a: String, _ b: String) -> Bool {
            a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        switch sortKey {
        case .manual: break
        case .creative: list.sort { before($0.displayName, $1.displayName) }
        case .original: list.sort { before($0.originalName, $1.originalName) }
        case .bpm: list.sort { ($0.bpm ?? 0) < ($1.bpm ?? 0) }
        case .duration: list.sort { $0.duration < $1.duration }
        case .added: list.sort { $0.dateAdded < $1.dateAdded }
        }
        if sortKey != .manual && !ascending { list.reverse() }
        return list
    }

    private var canReorder: Bool { sortKey == .manual && search.isEmpty }

    var body: some View {
        let songs = shown
        VStack(spacing: 0) {
            header(songs)
            columnHeader
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if baseSongs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            SongRow(song: song,
                                    queue: songs,
                                    playlistID: playlistID,
                                    canReorder: canReorder,
                                    isSelected: selection == song.id,
                                    onSelect: { selection = song.id },
                                    onDelete: { songToDelete = song })
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(
            LinearGradient(colors: [Theme.blue.opacity(0.20), Theme.background],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
                .ignoresSafeArea()
        )
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.cyan, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Theme.cyan.opacity(0.06))
                    .padding(10)
                    .allowsHitTesting(false)
                    .overlay {
                        Text("Drop music to add it to Ensemble")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.cyan)
                    }
            }
        }
        .onDrop(of: [.fileURL], delegate: LibraryDropDelegate(library: library,
                                                              selected: selection,
                                                              targeted: $dropTargeted))
        .alert("Delete this song?", isPresented: Binding(get: { songToDelete != nil },
                                                          set: { if !$0 { songToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let song = songToDelete {
                    player.stopIfNeeded(removed: [song.id])
                    library.delete([song.id])
                }
                songToDelete = nil
            }
            Button("Cancel", role: .cancel) { songToDelete = nil }
        } message: {
            Text("\"\(songToDelete?.displayName ?? "")\" will be removed from Ensemble and all playlists. Your original file is not touched.")
        }
    }

    // MARK: - Header

    private func header(_ songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer().frame(height: 22)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist == nil ? "LIBRARY" : "PLAYLIST")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                    Text(playlist?.name ?? "Your Music")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    let total = songs.reduce(0) { $0 + $1.duration }
                    Text("\(songs.count) song\(songs.count == 1 ? "" : "s") · \(durationText(total))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassPanel(radius: 20)

                Button { library.showImporter = true } label: {
                    Label("Import", systemImage: "plus")
                }
                .buttonStyle(GhostButtonStyle())
            }

            HStack(spacing: 12) {
                Button {
                    guard let first = songs.first else { return }
                    player.shuffle = false
                    player.play(first, in: songs)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.black)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Theme.gradient))
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
                .help("Play all")

                Button {
                    guard let pick = songs.randomElement() else { return }
                    player.shuffle = true
                    player.play(pick, in: songs)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
                .help("Shuffle play")
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Button {
                sortKey = .manual
                ascending = true
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(sortKey == .manual ? Theme.cyan : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Manual order (drag songs to rearrange)")
            .frame(width: Col.art)

            headerButton("Creative name", .creative).frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            headerButton("Original name", .original).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            headerButton("BPM", .bpm).frame(width: Col.bpm, alignment: .leading)
            headerButton("Time", .duration).frame(width: Col.time, alignment: .leading)
            headerButton("Date added", .added).frame(width: Col.date, alignment: .leading)
            Text("NOTES")
                .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
    }

    private func headerButton(_ title: String, _ key: SortKey) -> some View {
        Button {
            if sortKey == key {
                ascending.toggle()
            } else {
                sortKey = key
                ascending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(title.uppercased())
                if sortKey == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(sortKey == key ? Theme.cyan : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: playlist == nil ? "square.and.arrow.down.on.square" : "music.note.list")
                .font(.system(size: 54))
                .foregroundStyle(Theme.gradient)
            Text(playlist == nil ? "Drag songs here to start your library" : "This playlist is empty")
                .font(.title3.weight(.semibold))
            Text(playlist == nil
                 ? "Drop audio files or folders anywhere in this window, or use Import."
                 : "Drag songs from Your Music onto this playlist in the sidebar.")
                .foregroundStyle(Theme.textSecondary)
            if playlist == nil {
                Button("Import Music") { library.showImporter = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func durationText(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "\(minutes / 60) hr \(minutes % 60) min" }
        return "\(minutes) min"
    }
}

// MARK: - Row

struct SongRow: View {
    let song: Song
    let queue: [Song]
    let playlistID: UUID?
    let canReorder: Bool
    let isSelected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerService
    @State private var hovering = false

    private var isCurrent: Bool { player.currentID == song.id }

    var body: some View {
        HStack(spacing: 12) {
            artCell
                .frame(width: Col.art, alignment: .leading)

            TextField(library.analyzing.contains(song.id) ? "Naming…" : "Untitled",
                      text: binding(\.creativeName))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isCurrent ? Theme.cyan : Theme.textPrimary)
                .editableChrome()
                .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)

            TextField("Original name", text: binding(\.originalName))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .editableChrome()
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            Group {
                if library.analyzing.contains(song.id) && song.bpm == nil {
                    ProgressView().controlSize(.small)
                } else {
                    TextField("—", text: bpmBinding)
                        .textFieldStyle(.plain)
                        .editableChrome()
                }
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .frame(width: Col.bpm, alignment: .leading)

            Text(formatTime(song.duration))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Col.time, alignment: .leading)

            Text(song.dateAdded.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Col.date, alignment: .leading)

            Text(song.notes)
                .font(.system(size: 12))
                .foregroundStyle(Theme.cyan.opacity(0.9))
                .lineLimit(1)
                .help(song.notes)
                .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .background(
            Rectangle().fill(isSelected ? Theme.blue.opacity(0.28)
                             : (hovering ? Theme.blue.opacity(0.10) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Double-click anywhere that isn't a text field plays the song.
        .onTapGesture(count: 2) { play() }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
            onSelect()
        }
        .onDrop(of: [.plainText, .fileURL],
                delegate: RowDropDelegate(songID: song.id, playlistID: playlistID,
                                          canReorder: canReorder, library: library))
        .contextMenu { menu }
    }

    // MARK: Pieces

    private var artCell: some View {
        ZStack {
            ArtView(song: song, size: 40)
            if hovering || isCurrent {
                Color.black.opacity(0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 40, height: 40)
                Button {
                    if isCurrent { player.togglePlay() } else { play() }
                } label: {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        // Drag from the artwork to move the song or add it to a playlist.
        .onDrag { NSItemProvider(object: song.id.uuidString as NSString) }
        .contextMenu {
            Button("Choose Cover Art…") { chooseCover() }
            if song.hasArt {
                Button("Export Cover (3000×3000)…") { library.exportCover(for: song.id) }
                Button("Remove Cover Art", role: .destructive) { library.removeCover(for: song.id) }
            }
        }
        .help("Drag to rearrange or add to a playlist. Drop a picture on this row for cover art.")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Play") { play() }
        Menu("Add to Playlist") {
            ForEach(library.playlists) { playlist in
                Button(playlist.name) { library.add(song.id, toPlaylist: playlist.id) }
            }
            if !library.playlists.isEmpty { Divider() }
            Button("New Playlist…") {
                let playlist = library.createPlaylist(named: "New Playlist")
                library.add(song.id, toPlaylist: playlist.id)
            }
        }
        if let playlistID {
            Button("Remove from This Playlist") { library.remove(song.id, fromPlaylist: playlistID) }
        }
        Divider()
        Button("Choose Cover Art…") { chooseCover() }
        if song.hasArt {
            Button("Export Cover (3000×3000)…") { library.exportCover(for: song.id) }
            Button("Remove Cover Art") { library.removeCover(for: song.id) }
        }
        Divider()
        Button("Generate a New Creative Name") { library.analyze(song.id, rename: true) }
        Button("Re-detect BPM") { library.analyze(song.id) }
        Button("Show File in Finder") { NSWorkspace.shared.activateFileViewerSelecting([song.url]) }
        Divider()
        Button("Delete from Ensemble…", role: .destructive) { onDelete() }
    }

    private func play() {
        onSelect()
        player.play(song, in: queue)
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture. Ensemble converts it to 3000×3000."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            library.setCover(from: url, for: song.id)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<Song, String>) -> Binding<String> {
        Binding(get: { song[keyPath: keyPath] },
                set: { newValue in library.update(song.id) { $0[keyPath: keyPath] = newValue } })
    }

    private var bpmBinding: Binding<String> {
        Binding(get: { song.bpm.map(String.init) ?? "" },
                set: { newValue in
                    let digits = newValue.filter(\.isNumber)
                    library.update(song.id) { $0.bpm = Int(digits) }
                })
    }
}

private extension View {
    /// Faint field background so it's clear names can be clicked and edited.
    func editableChrome() -> some View {
        self.padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
    }
}
