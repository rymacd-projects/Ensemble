import SwiftUI
import UniformTypeIdentifiers

/// Cover art thumbnail with a black/blue placeholder.
struct ArtView: View {
    let song: Song?
    var size: CGFloat = 40
    var radius: CGFloat = 6

    var body: some View {
        ZStack {
            if let song, let image = ThumbnailCache.image(for: song) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.blue.opacity(0.55), Color.black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Theme.cyan.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Click or drag anywhere on the bar to jump to that point.
struct ScrubBar: View {
    var value: Double
    var total: Double
    var onSeek: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: 4)
                Capsule().fill(Theme.gradient)
                    .frame(width: max(4, geo.size.width * fraction), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, geo.size.width * fraction - 6))
                    .opacity(hovering || dragFraction != nil ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragFraction = min(max(drag.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { drag in
                        let end = min(max(drag.location.x / geo.size.width, 0), 1)
                        dragFraction = nil
                        onSeek(end * total)
                    }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: 16)
    }
}

// MARK: - Drag and drop helpers

enum DropLoader {
    /// Reads file URLs out of dropped items (from Finder, for example).
    static func fileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var found: URL?
                if let data = item as? Data {
                    found = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    found = url
                }
                if let found {
                    lock.lock(); urls.append(found); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

/// Dropping on a song row: songs reorder (landing just above this row), images become
/// cover art, audio files import.
struct RowDropDelegate: DropDelegate {
    let songID: UUID
    let playlistID: UUID?
    let canReorder: Bool
    let library: LibraryStore
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) || (canReorder && info.hasItemsConforming(to: [.plainText]))
    }

    func dropEntered(info: DropInfo) {
        if canReorder && info.hasItemsConforming(to: [.plainText]) { targeted = true }
    }

    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if info.hasItemsConforming(to: [.fileURL]) {
            DropLoader.fileURLs(from: info.itemProviders(for: [.fileURL])) { urls in
                Task { await library.handleDrop(urls, target: songID) }
            }
            return true
        }
        guard canReorder, let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let dragged = UUID(uuidString: text) else { return }
            Task { @MainActor in library.move(dragged, before: songID, in: playlistID) }
        }
        return true
    }
}

/// The empty strip under the last song: drop here to move a song to the very bottom.
struct EndDropDelegate: DropDelegate {
    let playlistID: UUID?
    let canReorder: Bool
    let library: LibraryStore
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        canReorder && info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let dragged = UUID(uuidString: text) else { return }
            Task { @MainActor in library.reposition(dragged, .bottom, in: playlistID) }
        }
        return true
    }
}

/// Dropping on the library background: audio files and folders import.
struct LibraryDropDelegate: DropDelegate {
    let library: LibraryStore
    let selected: UUID?
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        DropLoader.fileURLs(from: info.itemProviders(for: [.fileURL])) { urls in
            Task { await library.handleDrop(urls, target: selected) }
        }
        return true
    }
}
