import Foundation
import AVFoundation
import ShazamKit
import AppKit

struct SampleMatch: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var appleMusicURL: URL?
    var shazamURL: URL?
    /// Where in YOUR song this match was heard, in seconds.
    var firstHeard: Double
    var lastHeard: Double
}

/// Listens to a song in short windows and asks Shazam's catalog what it hears.
/// Anything recognised other than your own track is a candidate sample.
@MainActor
final class SampleFinder: ObservableObject {
    @Published private(set) var matches: [SampleMatch] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var isScanning = false
    @Published private(set) var finished = false
    @Published var errorText: String?

    private var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        matches = []
        progress = 0
        isScanning = false
        finished = false
        errorText = nil
    }

    func scan(_ song: Song) {
        reset()
        isScanning = true
        let url = song.url
        task = Task { [weak self] in
            do {
                try await self?.run(url: url)
            } catch is CancellationError {
                // cancelled
            } catch {
                self?.errorText = error.localizedDescription
            }
            self?.isScanning = false
            self?.finished = true
        }
    }

    func cancel() {
        task?.cancel()
        isScanning = false
    }

    private func run(url: URL) async throws {
        let file = try AVAudioFile(forReading: url)
        let sourceRate = file.processingFormat.sampleRate
        let totalSeconds = Double(file.length) / sourceRate
        guard totalSeconds > 3 else { throw ScanError.tooShort }

        let window = min(10.0, totalSeconds)
        let maxWindows = 60.0
        let stride = max(6.0, (totalSeconds - window) / (maxWindows - 1))
        var starts: [Double] = []
        var t = 0.0
        while t + window <= totalSeconds + 0.01 {
            starts.append(t)
            t += stride
        }
        if starts.isEmpty { starts = [0] }

        let session = SHSession()
        var found: [String: SampleMatch] = [:]
        var lastError: Error?
        var failures = 0

        for (index, start) in starts.enumerated() {
            try Task.checkCancellation()
            let buffer = try Self.readWindow(file: file, start: start, seconds: window)
            let generator = SHSignatureGenerator()
            try generator.append(buffer, at: nil)
            let result = await session.result(from: generator.signature())

            switch result {
            case .match(let match):
                for item in match.mediaItems {
                    let key = item.shazamID ?? "\(item.title ?? "")-\(item.artist ?? "")"
                    if var existing = found[key] {
                        existing.lastHeard = start + window
                        found[key] = existing
                    } else {
                        found[key] = SampleMatch(
                            id: key,
                            title: item.title ?? "Unknown title",
                            artist: item.artist ?? "Unknown artist",
                            appleMusicURL: item.appleMusicURL,
                            shazamURL: item.webURL,
                            firstHeard: start,
                            lastHeard: start + window)
                    }
                }
            case .noMatch:
                break
            case .error(let error, _):
                lastError = error
                failures += 1
            }

            matches = found.values.sorted { $0.firstHeard < $1.firstHeard }
            progress = Double(index + 1) / Double(starts.count)
        }

        if failures == starts.count, let lastError {
            throw ScanError.shazam(lastError.localizedDescription)
        }
    }

    enum ScanError: LocalizedError {
        case tooShort
        case shazam(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .tooShort: return "That song is too short to scan."
            case .unreadable: return "The audio couldn't be read."
            case .shazam(let reason):
                return "Shazam couldn't be reached (\(reason)). Check your internet connection. " +
                       "If this keeps happening, see the Sample Finder notes in the README."
            }
        }
    }

    /// Reads `seconds` of audio starting at `start`, converted to mono 44.1 kHz for Shazam.
    nonisolated private static func readWindow(file: AVAudioFile, start: Double, seconds: Double) throws -> AVAudioPCMBuffer {
        let inFormat = file.processingFormat
        let frames = AVAudioFrameCount(seconds * inFormat.sampleRate)
        file.framePosition = AVAudioFramePosition(start * inFormat.sampleRate)
        guard let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else {
            throw ScanError.unreadable
        }
        try file.read(into: input, frameCount: frames)

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw ScanError.unreadable
        }
        let outCapacity = AVAudioFrameCount(seconds * 44100) + 2048
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw ScanError.unreadable
        }
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if conversionError != nil { throw ScanError.unreadable }
        return output
    }
}

/// Builders for the WhoSampled and Google lookups.
enum SampleLinks {
    static func whoSampled(_ query: String) -> URL? {
        var components = URLComponents(string: "https://www.whosampled.com/search/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func google(_ query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
