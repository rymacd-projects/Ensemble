import SwiftUI

/// The Spotify-style bar pinned to the bottom of the window.
struct PlayerBar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerService

    private var song: Song? { library.song(player.currentID) }

    var body: some View {
        HStack(spacing: 20) {
            // Now playing
            HStack(spacing: 12) {
                ArtView(song: song, size: 54, radius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song?.displayName ?? "Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 280)

            // Controls and scrub bar
            VStack(spacing: 6) {
                HStack(spacing: 26) {
                    Button { player.shuffle.toggle() } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(player.shuffle ? Theme.cyan : Theme.textSecondary)
                    }
                    .help("Shuffle")

                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    .help("Previous (or restart)")

                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.black)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.gradient))
                    }
                    .help("Play / pause (Space)")

                    Button { player.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                    .help("Next")

                    Button { player.repeatMode = player.repeatMode.next } label: {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(player.repeatMode == .off ? Theme.textSecondary : Theme.cyan)
                    }
                    .help("Repeat: \(player.repeatMode.rawValue)")
                }
                .buttonStyle(.plain)
                .font(.system(size: 15))
                .disabled(song == nil)

                HStack(spacing: 10) {
                    Text(formatTime(player.currentTime))
                        .frame(width: 40, alignment: .trailing)
                    ScrubBar(value: player.currentTime, total: player.duration) { player.seek(to: $0) }
                    Text(formatTime(player.duration))
                        .frame(width: 40, alignment: .leading)
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .opacity(song == nil ? 0.4 : 1)
                .allowsHitTesting(song != nil)
            }
            .frame(maxWidth: .infinity)

            // Volume
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)
                ScrubBar(value: player.volume, total: 1) { player.volume = $0 }
                    .frame(width: 110)
            }
            .frame(width: 220)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(height: 84)
        .background(
            ZStack {
                LinearGradient(colors: [Theme.panel, Theme.background], startPoint: .top, endPoint: .bottom)
                WaveBackground(isPlaying: player.isPlaying, spectrum: player.spectrum, player: player)
                    .allowsHitTesting(false)
            }
        )
    }

    private var subtitle: String {
        guard let song else { return "Space plays/pauses · Enter restarts · ←/→ skip 5s" }
        if let bpm = song.bpm { return "\(bpm) BPM · \(song.originalName)" }
        return song.originalName
    }
}

/// Soft, translucent bars behind the player bar. Each bar stays in place and rises and falls
/// with one pitch band of the music that is playing (low notes on the left, high on the right).
struct WaveBackground: View {
    let isPlaying: Bool
    let spectrum: SpectrumData?
    let player: PlayerService

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { _ in
            let time = player.liveTime()
            Canvas { context, size in
                let barWidth: CGFloat = 3
                let step: CGFloat = 7
                let count = max(2, Int(size.width / step))
                let midY = size.height / 2
                let gradient = Gradient(colors: [Theme.cyan.opacity(0.28), Theme.blue.opacity(0.12)])
                let shading = GraphicsContext.Shading.linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0))

                for i in 0..<count {
                    var level: CGFloat = 0
                    if let spectrum {
                        let position = Double(i) / Double(count - 1) * Double(spectrum.bands - 1)
                        let low = Int(position)
                        let high = min(low + 1, spectrum.bands - 1)
                        let blend = Float(position - Double(low))
                        let a = spectrum.level(at: time, band: low)
                        let b = spectrum.level(at: time, band: high)
                        level = CGFloat(a + (b - a) * blend)
                    }
                    // A thin resting line, growing to about half the bar's height at the loudest.
                    let height = 4 + level * size.height * 0.5
                    let rect = CGRect(x: CGFloat(i) * step, y: midY - height / 2,
                                      width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: shading)
                }
            }
        }
    }
}
