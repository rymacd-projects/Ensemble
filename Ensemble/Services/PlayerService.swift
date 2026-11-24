import Foundation
import AVFoundation
import AppKit
import MediaPlayer

enum RepeatMode: String {
    case off, all, one
    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Plays a queue of songs with shuffle, repeat, seeking and keyboard shortcuts.
@MainActor
final class PlayerService: ObservableObject {
    @Published private(set) var currentID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var shuffle = false { didSet { if shuffle != oldValue { rebuildOrder() } } }
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.8 { didSet { player.volume = Float(volume) } }

    private var queue: [Song] = []
    private var order: [Int] = []
    private var position = 0

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    init() {
        player.volume = Float(volume)
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if time.seconds.isFinite { self.currentTime = time.seconds }
            }
        }
        configureRemoteCommands()
        installKeyMonitor()
    }

    // MARK: - Transport

    /// Starts `song`, using `list` (in the order shown on screen) as the queue.
    func play(_ song: Song, in list: [Song]) {
        queue = list
        guard let index = list.firstIndex(where: { $0.id == song.id }) else { return }
        order = Array(queue.indices)
        position = index
        if shuffle { rebuildOrder() }
        load(queue[order[position]])
    }

    func togglePlay() {
        guard currentID != nil else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    /// Enter key: start the current song again from 0:00.
    func restart() {
        guard currentID != nil else { return }
        seek(to: 0)
        player.play()
        isPlaying = true
    }

    func next() { advance(automatic: false) }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 || position == 0 {
            seek(to: 0)
        } else {
            position -= 1
            load(queue[order[position]])
        }
    }

    func seek(to seconds: Double) {
        let upper = duration > 0 ? duration : seconds
        let target = min(max(0, seconds), upper)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
    }

    /// Call when songs are deleted so the player never points at a missing file.
    func stopIfNeeded(removed ids: Set<UUID>) {
        guard let currentID, ids.contains(currentID) else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        self.currentID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Queue

    private func advance(automatic: Bool) {
        guard !queue.isEmpty else { return }
        if position + 1 < order.count {
            position += 1
            load(queue[order[position]])
        } else if repeatMode == .all || !automatic {
            if shuffle { order.shuffle() }
            position = 0
            load(queue[order[position]])
        } else {
            player.pause()
            seek(to: 0)
            isPlaying = false
        }
    }

    private func rebuildOrder() {
        guard !queue.isEmpty else { return }
        let currentIndex = order.indices.contains(position) ? order[position] : 0
        order = Array(queue.indices)
        if shuffle {
            order.shuffle()
            if let i = order.firstIndex(of: currentIndex) { order.swapAt(0, i) }
            position = 0
        } else {
            position = currentIndex
        }
    }

    private func load(_ song: Song) {
        currentID = song.id
        duration = song.duration
        currentTime = 0

        let item = AVPlayerItem(url: song.url)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.songEnded() }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.displayName,
            MPMediaItemPropertyPlaybackDuration: song.duration
        ]
    }

    private func songEnded() {
        if repeatMode == .one {
            seek(to: 0)
            player.play()
        } else {
            advance(automatic: true)
        }
    }

    // MARK: - Keyboard

    /// Space = pause/play, Return = restart, Left/Right = jump 5 seconds.
    /// Ignored while you're typing in a text field (for example renaming a song).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                // Only act in Ensemble's main window: never in sheets (like the website
                // upload browser), alerts, or file panels, where Space/Return mean something else.
                guard let window = NSApp.keyWindow,
                      !(window is NSPanel), !window.isSheet, window.attachedSheet == nil else { return event }
                if window.firstResponder is NSText { return event }
                let blocked: NSEvent.ModifierFlags = [.command, .option, .control]
                if !event.modifierFlags.intersection(blocked).isEmpty { return event }
                switch event.keyCode {
                case 49: self.togglePlay(); return nil
                case 36, 76: self.restart(); return nil
                case 123: self.seek(to: self.currentTime - 5); return nil
                case 124: self.seek(to: self.currentTime + 5); return nil
                default: return event
                }
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if let self, !self.isPlaying { self.togglePlay() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.isPlaying { self.togglePlay() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
    }
}
