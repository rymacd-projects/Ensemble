import SwiftUI
import UniformTypeIdentifiers

/// Sizes of the fixed parts of the list (the artwork column and the + button).
enum Col {
    static let art: CGFloat = 52
    static let addButton: CGFloat = 28
}

struct LibraryView: View {
    let playlistID: UUID?

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var layout: ColumnLayout

    /// Id of the column the list is sorted by. nil means your own order (newest on top).
    @State private var sortColumn: String?
    @State private var ascending = true
    @State private var search = ""
    @State private var selection: UUID?
    @State private var dropTargeted = false
    @State private var endDropTargeted = false
    @State private var songToDelete: Song?
    @State private var columnDropTarget: String?
    @State private var showAddColumn = false
    @State private var newColumnName = ""
    @State private var renamingColumn: ColumnSpec?
    @State private var renameText = ""
    @State private var columnToDelete: ColumnSpec?

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
                layout.columns.contains { song.columnText($0.id).localizedCaseInsensitiveContains(search) }
            }
        }
        if let id = sortColumn {
            switch id {
            case "bpm": list.sort { ($0.bpm ?? 0) < ($1.bpm ?? 0) }
            case "time": list.sort { $0.duration < $1.duration }
            case "date": list.sort { $0.dateAdded < $1.dateAdded }
            default:
                list.sort {
                    $0.columnText(id).localizedCaseInsensitiveCompare($1.columnText(id)) == .orderedAscending
                }
            }
            if !ascending { list.reverse() }
        }
        return list
    }

    /// Dragging songs up and down only makes sense in your own order (not while sorted or searching).
    private var canReorder: Bool { sortColumn == nil && search.isEmpty }

    var body: some View {
        let songs = shown
        VStack(spacing: 0) {
            header(songs)

            // The table scrolls sideways when the window is narrower than the columns.
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        columnHeader
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        if baseSongs.isEmpty {
                            emptyState
                        } else {
                            rowsList(songs)
                        }
                    }
                    .frame(minWidth: geo.size.width,
                           minHeight: geo.size.height,
                           maxHeight: geo.size.height,
                           alignment: .topLeading)
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

    private func rowsList(_ songs: [Song]) -> some View {
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
                // Drop a song here to send it to the very bottom.
                Rectangle()
                    .fill(endDropTargeted ? Theme.cyan : Color.clear)
                    .frame(height: endDropTargeted ? 3 : 48)
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText],
                            delegate: EndDropDelegate(playlistID: playlistID,
                                                      canReorder: canReorder,
                                                      library: library,
                                                      targeted: $endDropTargeted))
            }
            .padding(.bottom, 20)
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
                    if !canReorder {
                        Text("Dragging songs to reorder is off while sorted or searching. Press the ⇅ button to go back to your own order.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                        .frame(width: 140)
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

    // MARK: - Column headings

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Button {
                sortColumn = nil
                ascending = true
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(sortColumn == nil ? Theme.cyan : Theme.textSecondary)
                    .frame(width: Col.art, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Your own order (newest on top). Drag songs to rearrange.")

            ForEach(layout.columns) { spec in
                headerCell(spec)
            }

            // + adds a column of your own. Dropping a heading here moves it to the far right.
            Button {
                newColumnName = ""
                showAddColumn = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: Col.addButton, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a column")
            .onDrop(of: [.plainText],
                    delegate: ColumnDropDelegate(targetID: nil, layout: layout,
                                                 targeted: columnTargetBinding("end")))
            .alert("New Column", isPresented: $showAddColumn) {
                TextField("Column name", text: $newColumnName)
                Button("Add") { layout.addCustom(title: newColumnName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name it anything you like, then type a value for each song.")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .alert("Rename Column", isPresented: Binding(get: { renamingColumn != nil },
                                                      set: { if !$0 { renamingColumn = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let column = renamingColumn { layout.rename(column.id, to: renameText) }
                renamingColumn = nil
            }
            Button("Cancel", role: .cancel) { renamingColumn = nil }
        }
    }

    /// One column heading. Click to sort, drag it to move the column, drag its right edge to
    /// resize, double-click that edge to fit the widest text.
    private func headerCell(_ spec: ColumnSpec) -> some View {
        let active = sortColumn == spec.id
        return HStack(spacing: 4) {
            Text(spec.title.uppercased())
                .lineLimit(1)
            if active {
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(active ? Theme.cyan : Theme.textSecondary)
        .padding(.trailing, 8)
        .frame(width: spec.width, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if columnDropTarget == spec.id {
                Rectangle().fill(Theme.cyan).frame(width: 2)
            }
        }
        .overlay(alignment: .trailing) {
            ResizeHandle(layout: layout, columnID: spec.id) {
                layout.setWidth(spec.id, autoFitWidth(spec))
            }
        }
        .onTapGesture {
            if sortColumn == spec.id {
                ascending.toggle()
            } else {
                sortColumn = spec.id
                ascending = true
            }
        }
        .onDrag { NSItemProvider(object: "col:\(spec.id)" as NSString) }
        .onDrop(of: [.plainText],
                delegate: ColumnDropDelegate(targetID: spec.id, layout: layout,
                                             targeted: columnTargetBinding(spec.id)))
        .contextMenu {
            Button("Fit Column to Its Text") { layout.setWidth(spec.id, autoFitWidth(spec)) }
            if spec.isCustom {
                Button("Rename Column…") {
                    renameText = spec.title
                    renamingColumn = spec
                }
                Button("Delete Column…", role: .destructive) { columnToDelete = spec }
            }
            Divider()
            Button("Reset Column Layout") { layout.reset() }
        }
        .help("Click to sort. Drag to move. Drag the right edge to resize, double-click it to fit.")
        .alert("Delete this column?", isPresented: Binding(get: { columnToDelete?.id == spec.id },
                                                            set: { if !$0 { columnToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if sortColumn == spec.id { sortColumn = nil }
                layout.remove(spec.id)
                columnToDelete = nil
            }
            Button("Cancel", role: .cancel) { columnToDelete = nil }
        } message: {
            Text("\"\(spec.title)\" and everything typed in it will be removed from the list.")
        }
    }

    private func columnTargetBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { columnDropTarget == id },
                set: { isTarget in
                    if isTarget {
                        columnDropTarget = id
                    } else if columnDropTarget == id {
                        columnDropTarget = nil
                    }
                })
    }

    /// Width that fits the heading and the widest text in the column, like double-clicking
    /// a column edge in a spreadsheet.
    private func autoFitWidth(_ spec: ColumnSpec) -> CGFloat {
        let headingFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        var widest = (spec.title.uppercased() as NSString).size(withAttributes: [.font: headingFont]).width + 24

        let bodyFont: NSFont
        switch spec.id {
        case "creative": bodyFont = .systemFont(ofSize: 14, weight: .semibold)
        case "date", "uploaded", "notes": bodyFont = .systemFont(ofSize: 12)
        default: bodyFont = spec.isCustom ? .systemFont(ofSize: 12) : .systemFont(ofSize: 13)
        }
        let editable = spec.id == "creative" || spec.id == "notes" || spec.isCustom
        let padding: CGFloat = editable ? 24 : 8
        for song in library.songs {
            let width = (song.columnText(spec.id) as NSString).size(withAttributes: [.font: bodyFont]).width
            widest = max(widest, width + padding)
        }
        return ceil(widest)
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

// MARK: - Column resizing and moving

/// The draggable edge on the right of a column heading.
struct ResizeHandle: View {
    let layout: ColumnLayout
    let columnID: String
    var onAutoFit: () -> Void

    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? Theme.cyan : Theme.hairline)
            .frame(width: 2, height: 16)
            .padding(.horizontal, 5)
            .frame(height: 24)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside && !hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !inside && hovering {
                    NSCursor.pop()
                }
                hovering = inside
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        if startWidth == nil { startWidth = layout.width(of: columnID) }
                        layout.setWidth(columnID, (startWidth ?? 120) + drag.translation.width)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .onTapGesture(count: 2) { onAutoFit() }
            .help("Drag to resize. Double-click to fit the text.")
    }
}

/// Dropping a dragged heading on another heading moves the column to that spot.
struct ColumnDropDelegate: DropDelegate {
    let targetID: String?   // nil = the far right
    let layout: ColumnLayout
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix("col:") else { return }
            let id = String(text.dropFirst(4))
            Task { @MainActor in layout.move(id, before: targetID) }
        }
        return true
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
    @EnvironmentObject private var layout: ColumnLayout
    @State private var hovering = false
    @State private var dropTargeted = false

    private var isCurrent: Bool { player.currentID == song.id }

    var body: some View {
        HStack(spacing: 12) {
            artCell
                .frame(width: Col.art, alignment: .leading)

            ForEach(layout.columns) { spec in
                cell(spec)
                    .frame(width: spec.width, alignment: .leading)
            }

            Color.clear.frame(width: Col.addButton)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Rectangle().fill(isSelected ? Theme.blue.opacity(0.28)
                             : (hovering ? Theme.blue.opacity(0.10) : .clear))
        )
        .overlay(alignment: .top) {
            // Shows where a dragged song will land.
            if dropTargeted {
                Rectangle().fill(Theme.cyan).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Double-click anywhere that isn't a text field plays the song.
        .onTapGesture(count: 2) { play() }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
            onSelect()
        }
        // Drag the row (grab anywhere outside a text field) to reorder it
        // or drop it onto a playlist in the sidebar.
        .onDrag({
            NSItemProvider(object: song.id.uuidString as NSString)
        }, preview: {
            Text(song.displayName)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.blue))
                .foregroundStyle(.white)
        })
        .onDrop(of: [.plainText, .fileURL],
                delegate: RowDropDelegate(songID: song.id, playlistID: playlistID,
                                          canReorder: canReorder, library: library,
                                          targeted: $dropTargeted))
        .contextMenu { menu }
    }

    // MARK: Cells

    /// What a column shows for this song. Creative name, Notes and your own columns are editable;
    /// original name, BPM, time, date and "Uploaded to" are locked.
    @ViewBuilder
    private func cell(_ spec: ColumnSpec) -> some View {
        switch spec.id {
        case "creative":
            TextField(library.analyzing.contains(song.id) ? "Naming…" : "Untitled",
                      text: creativeNameBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isCurrent ? Theme.cyan : Theme.textPrimary)
                .editableChrome()
        case "original":
            Text(song.originalName)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .help("\(song.originalName) (locked)")
        case "bpm":
            Group {
                if library.analyzing.contains(song.id) && song.bpm == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text(song.bpm.map(String.init) ?? "—")
                }
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        case "time":
            Text(formatTime(song.duration))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        case "date":
            Text(song.columnText("date"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        case "uploaded":
            Text(song.uploadSummary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.cyan.opacity(0.9))
                .lineLimit(1)
                .help(song.uploadSummary)
        case "notes":
            TextField("Add a note", text: notesBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .editableChrome()
        default:
            TextField("—", text: customBinding(spec.id))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .editableChrome()
        }
    }

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
        .contextMenu {
            Button("Choose Cover Art…") { chooseCover() }
            if song.hasArt {
                Button("Export Cover (3000×3000)…") { library.exportCover(for: song.id) }
                Button("Remove Cover Art", role: .destructive) { library.removeCover(for: song.id) }
            }
        }
        .help("Drop a picture on this row to set the cover art.")
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
        if canReorder {
            Menu("Move") {
                Button("To Top") { library.reposition(song.id, .top, in: playlistID) }
                Button("Up") { library.reposition(song.id, .up, in: playlistID) }
                Button("Down") { library.reposition(song.id, .down, in: playlistID) }
                Button("To Bottom") { library.reposition(song.id, .bottom, in: playlistID) }
            }
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

    private var creativeNameBinding: Binding<String> {
        Binding(get: { song.creativeName },
                set: { newValue in library.update(song.id) { $0.creativeName = newValue } })
    }

    private var notesBinding: Binding<String> {
        Binding(get: { song.userNotes ?? "" },
                set: { newValue in
                    library.update(song.id) { $0.userNotes = newValue.isEmpty ? nil : newValue }
                })
    }

    private func customBinding(_ columnID: String) -> Binding<String> {
        Binding(get: { song.customValues?[columnID] ?? "" },
                set: { newValue in
                    library.update(song.id) {
                        var values = $0.customValues ?? [:]
                        values[columnID] = newValue.isEmpty ? nil : newValue
                        $0.customValues = values.isEmpty ? nil : values
                    }
                })
    }
}

private extension View {
    /// Faint field background so it's clear which fields can be clicked and edited.
    func editableChrome() -> some View {
        self.padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
    }
}
