import SwiftUI
import WebKit

struct UploadView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var uploader: UploadService

    @State private var selectedSongs = Set<UUID>()
    @State private var selectedPlatforms = Set<Platform>()
    @State private var signingIn: Platform?
    @State private var batch: JobBatch?

    struct JobBatch: Identifiable {
        let id = UUID()
        let jobs: [UploadJob]
    }

    private var linkedSelected: [Platform] {
        Platform.allCases.filter { selectedPlatforms.contains($0) && uploader.isLinked($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ONLINE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.cyan)
                Text("Upload")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("Link your accounts once, pick songs, then choose where to post them.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("1. Linked accounts")
                    ForEach(Platform.allCases) { platform in
                        accountCard(platform)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 310)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle("2. Choose songs")
                        Spacer()
                        Button(selectedSongs.count == library.songs.count && !library.songs.isEmpty ? "Select none" : "Select all") {
                            if selectedSongs.count == library.songs.count {
                                selectedSongs.removeAll()
                            } else {
                                selectedSongs = Set(library.songs.map(\.id))
                            }
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(library.songs.isEmpty)
                    }
                    songList
                    sectionTitle("3. Choose where to post")
                    destinationChips
                    HStack {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("Start uploading") { startUpload() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(selectedSongs.isEmpty || linkedSelected.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Theme.blue.opacity(0.20), Theme.background],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
                .ignoresSafeArea()
        )
        .sheet(item: $signingIn) { platform in
            SignInSheet(platform: platform)
        }
        .sheet(item: $batch) { batch in
            UploadAssistantView(jobs: batch.jobs)
        }
    }

    private var summary: String {
        if selectedSongs.isEmpty { return "Select at least one song." }
        if selectedPlatforms.isEmpty { return "Pick a website. Only linked accounts can be used." }
        if linkedSelected.isEmpty { return "Link an account first." }
        let songs = selectedSongs.count
        return "\(songs) song\(songs == 1 ? "" : "s") to \(linkedSelected.map(\.name).joined(separator: ", "))"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
    }

    private func accountCard(_ platform: Platform) -> some View {
        let linked = uploader.isLinked(platform)
        return HStack(spacing: 12) {
            Image(systemName: platform.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Theme.cyan)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.blue.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.name).font(.system(size: 14, weight: .semibold))
                Text(linked ? "Connected" : platform.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(linked ? Theme.cyan : Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if linked {
                Button("Disconnect") { uploader.disconnect(platform); selectedPlatforms.remove(platform) }
                    .buttonStyle(GhostButtonStyle())
            } else {
                Button("Link") { signingIn = platform }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(12)
        .glassPanel()
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if library.songs.isEmpty {
                    Text("Import music in Your Music first.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(20)
                }
                ForEach(library.songs) { song in
                    let selected = selectedSongs.contains(song.id)
                    Button {
                        if selected { selectedSongs.remove(song.id) } else { selectedSongs.insert(song.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? Theme.cyan : Theme.textSecondary)
                            ArtView(song: song, size: 34, radius: 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text(song.uploadSummary.isEmpty ? song.originalName : song.uploadSummary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(song.uploadSummary.isEmpty ? Theme.textSecondary : Theme.cyan)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatTime(song.duration))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? Theme.blue.opacity(0.22) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .glassPanel()
    }

    private var destinationChips: some View {
        HStack(spacing: 8) {
            let linkedPlatforms = Platform.allCases.filter { uploader.isLinked($0) }
            let allSelected = !linkedPlatforms.isEmpty && linkedPlatforms.allSatisfy { selectedPlatforms.contains($0) }
            chip("All websites", on: allSelected, enabled: !linkedPlatforms.isEmpty) {
                if allSelected { selectedPlatforms.removeAll() } else { selectedPlatforms = Set(linkedPlatforms) }
            }
            ForEach(Platform.allCases) { platform in
                chip(platform.name, on: selectedPlatforms.contains(platform), enabled: uploader.isLinked(platform)) {
                    if selectedPlatforms.contains(platform) { selectedPlatforms.remove(platform) }
                    else { selectedPlatforms.insert(platform) }
                }
            }
            Spacer()
        }
    }

    private func chip(_ title: String, on: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.blue.opacity(0.12))))
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .foregroundStyle(on ? Color.black : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(enabled ? "" : "Link this account first")
    }

    private func startUpload() {
        let songs = library.songs.filter { selectedSongs.contains($0.id) }
        var jobs: [UploadJob] = []
        for song in songs {
            for platform in linkedSelected {
                jobs.append(UploadJob(songID: song.id, platform: platform))
            }
        }
        batch = JobBatch(jobs: jobs)
    }
}

// MARK: - Web view

struct WebContainer: NSViewRepresentable {
    let session: WebSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Sign in

struct SignInSheet: View {
    let platform: Platform
    @EnvironmentObject private var uploader: UploadService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = WebSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Link \(platform.name)").font(.headline)
                    Text("Sign in on the site below. Ensemble never sees your password; it only keeps the signed-in session.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if session.isLoading { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.buttonStyle(GhostButtonStyle())
                Button("I'm signed in") {
                    uploader.markLinked(platform)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(14)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            WebContainer(session: session)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Theme.background)
        .onAppear { session.load(platform.signInURL) }
    }
}

// MARK: - Upload assistant

/// Walks through each song/site pair. Ensemble opens the site's upload form and hands over
/// your file when the page asks for one; you review and press the site's own publish button.
struct UploadAssistantView: View {
    let jobs: [UploadJob]
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = WebSession()
    @State private var index = 0

    private var job: UploadJob? { jobs.indices.contains(index) ? jobs[index] : nil }
    private var song: Song? { library.song(job?.songID) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtView(song: song, size: 46, radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(song?.displayName ?? "") → \(job?.platform.name ?? "")")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Upload \(min(index + 1, jobs.count)) of \(jobs.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if session.isLoading { ProgressView().controlSize(.small) }
                Button("Close") { dismiss() }.buttonStyle(GhostButtonStyle())
            }
            .padding(14)

            Text("Open the site's upload form below. When it asks you to choose a file, Ensemble supplies the one selected here. Review the details, press the site's own Publish button, then come back and mark it uploaded.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            WebContainer(session: session)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 10) {
                Text("Next file picker uses:")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Picker("", selection: $session.pickerChoice) {
                    ForEach(WebSession.PickerChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)

                Button("Copy title") { copy(song?.displayName ?? "") }.buttonStyle(GhostButtonStyle())
                Button("Copy BPM") { copy(song?.bpm.map(String.init) ?? "") }.buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Skip") { advance(markUploaded: false) }.buttonStyle(GhostButtonStyle())
                Button(index + 1 >= jobs.count ? "Mark uploaded & finish" : "Mark uploaded & next") {
                    advance(markUploaded: true)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(14)
        }
        .frame(minWidth: 1000, minHeight: 720)
        .background(Theme.background)
        .onAppear { configure() }
    }

    private func configure() {
        guard let job, let song else { return }
        session.audioURL = song.url
        session.coverURL = song.hasArt ? song.artURL : nil
        session.pickerChoice = .audio
        session.load(job.platform.uploadURL)
    }

    private func advance(markUploaded: Bool) {
        if markUploaded, let job {
            library.recordUpload(songID: job.songID, platform: job.platform.name)
        }
        if index + 1 >= jobs.count {
            dismiss()
        } else {
            index += 1
            configure()
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
