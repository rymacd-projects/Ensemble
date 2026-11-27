import Foundation
import CoreGraphics

struct ColumnSpec: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var width: CGFloat

    /// Columns you add with the + button have ids starting with "custom:".
    var isCustom: Bool { id.hasPrefix("custom:") }
}

/// Which columns the song list shows, in what order and how wide. Saved between launches.
final class ColumnLayout: ObservableObject {
    static let minWidth: CGFloat = 56
    static let maxWidth: CGFloat = 900
    private static let storageKey = "columnLayout.v1"

    static let defaults: [ColumnSpec] = [
        ColumnSpec(id: "creative", title: "Creative name", width: 220),
        ColumnSpec(id: "original", title: "Original name", width: 180),
        ColumnSpec(id: "bpm", title: "BPM", width: 64),
        ColumnSpec(id: "time", title: "Time", width: 64),
        ColumnSpec(id: "date", title: "Date added", width: 108),
        ColumnSpec(id: "uploaded", title: "Uploaded to", width: 150),
        ColumnSpec(id: "notes", title: "Notes", width: 200)
    ]

    @Published private(set) var columns: [ColumnSpec] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([ColumnSpec].self, from: data), !saved.isEmpty {
            // Make sure every built-in column is still there.
            var list = saved
            for column in Self.defaults where !list.contains(where: { $0.id == column.id }) {
                list.append(column)
            }
            columns = list
        } else {
            columns = Self.defaults
        }
    }

    func width(of id: String) -> CGFloat {
        columns.first { $0.id == id }?.width ?? 120
    }

    func setWidth(_ id: String, _ width: CGFloat) {
        guard let i = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[i].width = min(max(width, Self.minWidth), Self.maxWidth)
    }

    /// Moves a column so it sits just before `target` (or at the far right when `target` is nil).
    func move(_ id: String, before target: String?) {
        guard id != target, let from = columns.firstIndex(where: { $0.id == id }) else { return }
        var list = columns
        let item = list.remove(at: from)
        if let target, let to = list.firstIndex(where: { $0.id == target }) {
            list.insert(item, at: to)
        } else {
            list.append(item)
        }
        columns = list
    }

    @discardableResult
    func addCustom(title: String) -> ColumnSpec {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let column = ColumnSpec(id: "custom:\(UUID().uuidString)",
                                title: trimmed.isEmpty ? "New column" : trimmed,
                                width: 160)
        columns.append(column)
        return column
    }

    func rename(_ id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[i].title = trimmed
    }

    func remove(_ id: String) {
        guard id.hasPrefix("custom:") else { return }
        columns.removeAll { $0.id == id }
    }

    /// Built-in columns back to their original order and widths. Your own columns stay, at the end.
    func reset() {
        let custom = columns.filter(\.isCustom).map { column -> ColumnSpec in
            var c = column
            c.width = 160
            return c
        }
        columns = Self.defaults + custom
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(columns) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
