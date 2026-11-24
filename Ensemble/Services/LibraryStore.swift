import Foundation
import AVFoundation
import AppKit

/// Owns every song and playlist: importing, editing, analysing and saving.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var analyzing: Set<UUID> = []
    @Published var message: String?
    @Published var showImporter = false

    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "alac", "mp4"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "gif", "bmp", "webp"]

    private var saveTask: Task<Void, Never>?

    init() { load() }

    func song(_ id: UUID?) -> Song? {
        guard let id else { return nil }
        return songs.first { $0.id == id }
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlist.songIDs.compactMap { id in songs.first { $0.id == id } }
    }

    // MARK: - Import

    /// Imports audio files (and folders of them). Images are ignored here.
    func importFiles(_ urls: [URL]) async {
        var failed: [String] = []
        for url in expand(urls) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard Self.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            do {
                let song = try await makeSong(from: url)
                songs.append(song)
                analyze(song.id)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        scheduleSave()
        if !failed.isEmpty { message = "Couldn't import: " + failed.joined(separator: ", ") }
    }

    /// Handles files dropped onto the app: images become `target`'s cover art, audio is imported.
    func handleDrop(_ urls: [URL], target: UUID?) async {
        let images = urls.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
        let others = urls.filter { !Self.imageExtensions.contains($0.pathExtension.lowercased()) }
        if let image = images.first {
            if let target {
                setCover(from: image, for: target)
            } else {
                message = "Drop a picture onto a song (or select a song first) to set its cover art."
            }
        }
        if !others.isEmpty { await importFiles(others) }
    }

    private func expand(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) {
                    for case let file as URL in walker { result.append(file) }
                }
            } else {
                result.append(url)
            }
        }
        return result
    }

    private func makeSong(from source: URL) async throws -> Song {
        let ext = source.pathExtension.lowercased()
        let stored = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: Paths.audio.appendingPathComponent(stored))
        let asset = AVURLAsset(url: Paths.audio.appendingPathComponent(stored))
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        return Song(originalName: source.lastPathComponent,
                    creativeName: "",
                    bpm: nil,
                    duration: seconds.isFinite ? seconds : 0,
                    audioFile: stored)
    }

    /// Detects BPM, then asks for a creative name (unless the user already typed one).
    func analyze(_ id: UUID, rename: Bool = false) {
        guard let song = song(id) else { return }
        analyzing.insert(id)
        let url = song.url
        let original = song.originalName
        let duration = song.duration
        Task { [self] in
            let bpm = await Task.detached(priority: .utility) { BPMDetector.detect(url: url) }.value
            update(id) { $0.bpm = bpm ?? $0.bpm }
            let currentName = self.song(id)?.creativeName ?? ""
            if rename || currentName.isEmpty {
                let name = await NameGenerator.generate(original: original, bpm: bpm, duration: duration)
                update(id) { $0.creativeName = name }
            }
            analyzing.remove(id)
        }
    }

    // MARK: - Editing

    func update(_ id: UUID, _ change: (inout Song) -> Void) {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        change(&songs[index])
        scheduleSave()
    }

    func delete(_ ids: Set<UUID>) {
        for song in songs where ids.contains(song.id) {
            try? FileManager.default.removeItem(at: song.url)
            CoverArt.remove(for: song)
        }
        songs.removeAll { ids.contains($0.id) }
        for i in playlists.indices { playlists[i].songIDs.removeAll { ids.contains($0) } }
        scheduleSave()
    }

    func recordUpload(songID: UUID, platform: String) {
        update(songID) { $0.uploads.append(UploadRecord(platform: platform, date: Date())) }
    }

    // MARK: - Cover art

    func setCover(from imageURL: URL, for id: UUID) {
        guard let song = song(id) else { return }
        let scoped = imageURL.startAccessingSecurityScopedResource()
        defer { if scoped { imageURL.stopAccessingSecurityScopedResource() } }
        guard let image = CoverArt.image(from: imageURL) else {
            message = "That image couldn't be read."
            return
        }
        setCover(image, for: song)
    }

    func setCover(_ image: CGImage, for song: Song) {
        do {
            try CoverArt.save(image, for: song)
            update(song.id) { $0.hasArt = true; $0.artRevision += 1 }
        } catch {
            message = error.localizedDescription
        }
    }

    func removeCover(for id: UUID) {
        guard let song = song(id) else { return }
        CoverArt.remove(for: song)
        update(id) { $0.hasArt = false; $0.artRevision += 1 }
    }

    func exportCover(for id: UUID) {
        guard let song = song(id), song.hasArt else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(song.displayName) cover 3000x3000.jpg"
        panel.allowedContentTypes = [.jpeg]
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: song.artURL, to: destination)
        }
    }

    // MARK: - Ordering and playlists

    /// Moves a song so it sits just before `target`, in the main library or a playlist.
    func move(_ id: UUID, before target: UUID, in playlistID: UUID?) {
        guard id != target else { return }
        if let playlistID, let p = playlists.firstIndex(where: { $0.id == playlistID }) {
            var ids = playlists[p].songIDs
            guard let from = ids.firstIndex(of: id) else { return }
            ids.remove(at: from)
            let to = ids.firstIndex(of: target) ?? ids.endIndex
            ids.insert(id, at: to)
            playlists[p].songIDs = ids
        } else {
            guard let from = songs.firstIndex(where: { $0.id == id }) else { return }
            let moving = songs.remove(at: from)
            let to = songs.firstIndex(where: { $0.id == target }) ?? songs.endIndex
            songs.insert(moving, at: to)
        }
        scheduleSave()
    }

    @discardableResult
    func createPlaylist(named name: String) -> Playlist {
        let playlist = Playlist(name: name.isEmpty ? "New Playlist" : name)
        playlists.append(playlist)
        scheduleSave()
        return playlist
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        playlists[i].name = name
        scheduleSave()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        scheduleSave()
    }

    func add(_ songID: UUID, toPlaylist id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }),
              !playlists[i].songIDs.contains(songID) else { return }
        playlists[i].songIDs.append(songID)
        scheduleSave()
    }

    func remove(_ songID: UUID, fromPlaylist id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].songIDs.removeAll { $0 == songID }
        scheduleSave()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var songs: [Song]
        var playlists: [Playlist]
    }

    private func load() {
        guard let data = try? Data(contentsOf: Paths.library),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        songs = snapshot.songs.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        playlists = snapshot.playlists
    }

    /// Saves shortly after the last change so typing in a name field doesn't write on every key.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snapshot = Snapshot(songs: songs, playlists: playlists)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Paths.library, options: .atomic)
    }
}
