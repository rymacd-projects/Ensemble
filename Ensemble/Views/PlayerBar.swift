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
            LinearGradient(colors: [Theme.panel, Theme.background], startPoint: .top, endPoint: .bottom)
        )
    }

    private var subtitle: String {
        guard let song else { return "Space plays/pauses · Enter restarts · ←/→ skip 5s" }
        if let bpm = song.bpm { return "\(bpm) BPM · \(song.originalName)" }
        return song.originalName
    }
}
