import Foundation
import WebKit
import AppKit

/// The four sites Ensemble can post to.
///
/// None of these services offers a public upload API, so Ensemble signs in through an
/// in-app browser (you type your password on the site itself, never into Ensemble) and
/// then hands your file to the site's own upload form. If a site ever publishes an
/// official API, it can be added behind this same type.
enum Platform: String, CaseIterable, Identifiable, Codable {
    case beatstars = "BeatStars"
    case traktrain = "Traktrain"
    case airbit = "Airbit"
    case distrokid = "DistroKid"

    var id: String { rawValue }
    var name: String { rawValue }

    var signInURL: URL {
        switch self {
        case .beatstars: return URL(string: "https://www.beatstars.com/login")!
        case .traktrain: return URL(string: "https://traktrain.com/login")!
        case .airbit: return URL(string: "https://airbit.com/login")!
        case .distrokid: return URL(string: "https://distrokid.com/signin/")!
        }
    }

    var uploadURL: URL {
        switch self {
        case .beatstars: return URL(string: "https://studio.beatstars.com/")!
        case .traktrain: return URL(string: "https://traktrain.com/upload")!
        case .airbit: return URL(string: "https://airbit.com/dashboard")!
        case .distrokid: return URL(string: "https://distrokid.com/new/")!
        }
    }

    /// Used to clear the saved session when you disconnect.
    var domainKeyword: String {
        switch self {
        case .beatstars: return "beatstars"
        case .traktrain: return "traktrain"
        case .airbit: return "airbit"
        case .distrokid: return "distrokid"
        }
    }

    var systemImage: String {
        switch self {
        case .beatstars: return "waveform"
        case .traktrain: return "train.side.front.car"
        case .airbit: return "airplane"
        case .distrokid: return "antenna.radiowaves.left.and.right"
        }
    }

    var hint: String {
        switch self {
        case .beatstars: return "Beats and licensing marketplace"
        case .traktrain: return "Beat marketplace"
        case .airbit: return "Beat store and licensing"
        case .distrokid: return "Distribution to Spotify, Apple Music and more"
        }
    }
}

struct UploadJob: Identifiable, Hashable {
    let id = UUID()
    let songID: UUID
    let platform: Platform
}

@MainActor
final class UploadService: ObservableObject {
    @Published private(set) var linked: Set<Platform> = []
    private let defaultsKey = "linkedPlatforms"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        linked = Set(saved.compactMap { Platform(rawValue: $0) })
    }

    func isLinked(_ platform: Platform) -> Bool { linked.contains(platform) }

    func markLinked(_ platform: Platform) {
        linked.insert(platform)
        persist()
    }

    /// Forgets the platform and wipes the browser session Ensemble saved for it.
    func disconnect(_ platform: Platform) {
        linked.remove(platform)
        persist()
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let matching = records.filter { $0.displayName.lowercased().contains(platform.domainKeyword) }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching) {}
        }
    }

    private func persist() {
        UserDefaults.standard.set(linked.map(\.rawValue), forKey: defaultsKey)
    }
}

/// Wraps a WKWebView and answers the site's "choose a file" prompt with your song or cover art.
/// (WebKit calls these delegate methods on the main thread.)
final class WebSession: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    enum PickerChoice: String, CaseIterable, Identifiable {
        case audio = "Song file"
        case cover = "Cover art"
        case ask = "Ask me"
        var id: String { rawValue }
    }

    let webView: WKWebView
    @Published var pickerChoice: PickerChoice = .audio
    @Published var isLoading = false
    var audioURL: URL?
    var coverURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        switch pickerChoice {
        case .audio:
            completionHandler(audioURL.map { [$0] })
        case .cover:
            completionHandler(coverURL.map { [$0] })
        case .ask:
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }
    }

    /// Keeps sign-in popups and "open in new window" links inside the same view.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
