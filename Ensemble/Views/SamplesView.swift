import SwiftUI

struct SamplesView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var finder = SampleFinder()
    @State private var selectedID: UUID?
    @State private var search = ""

    private var selected: Song? { library.song(selectedID) }

    private var songs: [Song] {
        guard !search.isEmpty else { return library.songs }
        return library.songs.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
            $0.originalName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 30)
                Text("Pick a song")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassPanel(radius: 18)
                .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if library.songs.isEmpty {
                            Text("Import music in Your Music first.")
                                .foregroundStyle(Theme.textSecondary)
                                .padding(16)
                        }
                        ForEach(songs) { song in
                            Button {
                                selectedID = song.id
                                finder.reset()
                            } label: {
                                HStack(spacing: 10) {
                                    ArtView(song: song, size: 36, radius: 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .lineLimit(1)
                                        Text(song.originalName)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(selectedID == song.id ? Theme.blue.opacity(0.28) : .clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 300)
            .background(Theme.sidebar.opacity(0.6))

            Rectangle().fill(Theme.hairline).frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(colors: [Theme.blue.opacity(0.20), Theme.background],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let song = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom, spacing: 18) {
                        ArtView(song: song, size: 120, radius: 12)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SAMPLE FINDER")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.cyan)
                            Text(song.displayName)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .lineLimit(2)
                            Text(song.originalName)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        if finder.isScanning {
                            Button("Stop") { finder.cancel() }.buttonStyle(GhostButtonStyle())
                        } else {
                            Button {
                                finder.scan(song)
                            } label: {
                                Label("Listen for samples", systemImage: "waveform.badge.magnifyingglass")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        Button {
                            SampleLinks.open(SampleLinks.whoSampled(song.displayName))
                        } label: { Label("Search WhoSampled", systemImage: "magnifyingglass") }
                            .buttonStyle(GhostButtonStyle())
                        Button {
                            SampleLinks.open(SampleLinks.google("\(song.displayName) sample"))
                        } label: { Label("Search Google", systemImage: "globe") }
                            .buttonStyle(GhostButtonStyle())
                    }

                    if finder.isScanning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: finder.progress)
                                .tint(Theme.cyan)
                            Text("Listening… \(Int(finder.progress * 100))%")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    if let error = finder.errorText {
                        Text(error)
                            .font(.system(size: 13))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassPanel()
                    }

                    if !finder.matches.isEmpty {
                        Text("Possible matches")
                            .font(.system(size: 15, weight: .semibold))
                        ForEach(finder.matches) { match in
                            matchCard(match)
                        }
                    } else if finder.finished && finder.errorText == nil {
                        Text("Nothing in Shazam's catalog matched this song. That doesn't prove there are no samples: chopped, pitched or heavily layered samples are often missed. Try the WhoSampled and Google buttons above.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(14)
                            .glassPanel()
                    }

                    Text("Ensemble listens to short slices of your song and asks Shazam what they sound like, then lets you check each result on WhoSampled and Google. WhoSampled has no public lookup service, so those two are opened in your browser. Treat matches as leads to confirm, not as legal clearance.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(28)
                .padding(.top, 14)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.gradient)
                Text("Select a song to check it for samples")
                    .font(.title3.weight(.semibold))
                Text("Ensemble will listen to it and look for matches.")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func matchCard(_ match: SampleMatch) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 20))
                .foregroundStyle(Theme.cyan)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.blue.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(match.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(match.artist).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Text("Heard in your song at \(formatTime(match.firstHeard))–\(formatTime(match.lastHeard))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.cyan)
            }
            Spacer()
            Button("WhoSampled") {
                SampleLinks.open(SampleLinks.whoSampled("\(match.title) \(match.artist)"))
            }.buttonStyle(GhostButtonStyle())
            Button("Google") {
                SampleLinks.open(SampleLinks.google("\(match.title) \(match.artist) sample"))
            }.buttonStyle(GhostButtonStyle())
            if let url = match.appleMusicURL ?? match.shazamURL {
                Button("Listen") { SampleLinks.open(url) }.buttonStyle(GhostButtonStyle())
            }
        }
        .padding(12)
        .glassPanel()
    }
}
