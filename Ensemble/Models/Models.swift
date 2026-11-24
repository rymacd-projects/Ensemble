import Foundation

/// Where Ensemble keeps its files (inside the app's sandbox container).
enum Paths {
    static let base: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ensemble", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let audio = folder("Audio")
    static let art = folder("Art")
    static let library = base.appendingPathComponent("library.json")

    private static func folder(_ name: String) -> URL {
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct UploadRecord: Codable, Hashable {
    var platform: String
    var date: Date
}

struct Song: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Name of the file as it was when imported.
    var originalName: String
    /// Creative title (AI-generated, editable).
    var creativeName: String
    var bpm: Int?
    var duration: Double
    var dateAdded = Date()
    /// File name of Ensemble's private copy of the audio.
    var audioFile: String
    var hasArt = false
    /// Bumped each time the cover changes so cached thumbnails refresh.
    var artRevision = 0
    var uploads: [UploadRecord] = []

    var url: URL { Paths.audio.appendingPathComponent(audioFile) }
    var artURL: URL { Paths.art.appendingPathComponent("\(id.uuidString).jpg") }
    var thumbURL: URL { Paths.art.appendingPathComponent("\(id.uuidString)_thumb.jpg") }

    /// Shown in the Notes column once the song has been posted somewhere.
    var notes: String {
        guard !uploads.isEmpty else { return "" }
        var seen = Set<String>()
        let names = uploads.map(\.platform).filter { seen.insert($0).inserted }
        return "Uploaded to " + names.joined(separator: ", ")
    }

    var displayName: String { creativeName.isEmpty ? originalName : creativeName }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var songIDs: [UUID] = []
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
