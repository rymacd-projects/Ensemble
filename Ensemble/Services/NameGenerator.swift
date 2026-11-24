import Foundation

/// Produces the "creative name" for a song.
///
/// With an Anthropic API key saved in Settings, Claude writes the title.
/// Without a key, a built-in generator makes a mood-based name offline.
enum NameGenerator {
    static let keyAccount = "anthropic-api-key"

    static func generate(original: String, bpm: Int?, duration: Double) async -> String {
        if let key = Keychain.get(keyAccount), !key.isEmpty,
           let name = await askClaude(original: original, bpm: bpm, duration: duration, key: key) {
            return name
        }
        return offlineName(original: original, bpm: bpm)
    }

    // MARK: - Claude

    private static func askClaude(original: String, bpm: Int?, duration: Double, key: String) async -> String? {
        let bpmText = bpm.map { "\($0) BPM" } ?? "unknown tempo"
        let prompt = """
        Invent one short, memorable, creative title (1 to 4 words) for a music track. \
        The producer's working file name is "\(original)". It runs \(Int(duration)) seconds at \(bpmText). \
        Reply with only the title, no quotes and no explanation.
        """
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": "claude-sonnet-5-5",
            "max_tokens": 40,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else { return nil }

        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Offline

    private static let slow = ["Velvet", "Midnight", "Hollow", "Drifting", "Amber", "Quiet", "Moonlit", "Faded"]
    private static let mid = ["Neon", "Golden", "Electric", "Silver", "Wandering", "Crystal", "Ember", "Cobalt"]
    private static let fast = ["Turbo", "Runaway", "Blazing", "Static", "Voltage", "Wildfire", "Rapid", "Kinetic"]
    private static let nouns = ["Skyline", "Horizon", "Echoes", "Pulse", "Gravity", "Mirage", "Orbit", "Signal",
                                "Tides", "Afterglow", "Palace", "Currents", "Harbor", "Daydream", "Avenue", "Static"]

    private static func offlineName(original: String, bpm: Int?) -> String {
        // Stable per file name, so the same track always gets the same suggestion.
        var hash: UInt64 = 5381
        for byte in original.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let words: [String]
        switch bpm ?? 110 {
        case ..<90: words = slow
        case 90..<125: words = mid
        default: words = fast
        }
        let adjective = words[Int(hash % UInt64(words.count))]
        let noun = nouns[Int((hash / 7) % UInt64(nouns.count))]
        return "\(adjective) \(noun)"
    }
}
