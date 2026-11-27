import SwiftUI

/// One color theme: a main accent and a lighter companion, over a near-black base
/// that picks up a faint tint of the accent.
struct Palette: Identifiable {
    let id: String
    let name: String
    let pr, pg, pb: Double   // main accent
    let sr, sg, sb: Double   // lighter companion accent

    var primary: Color { Color(red: pr, green: pg, blue: pb) }
    var secondary: Color { Color(red: sr, green: sg, blue: sb) }
    var background: Color { tint(0.012, 0.020) }
    var sidebar: Color { tint(0.020, 0.035) }
    var panel: Color { tint(0.040, 0.080) }

    private func tint(_ base: Double, _ amount: Double) -> Color {
        Color(red: base + amount * pr, green: base + amount * pg, blue: base + amount * pb)
    }

    private static func make(_ id: String, _ name: String,
                             _ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Palette {
        Palette(id: id, name: name, pr: a.0, pg: a.1, pb: a.2, sr: b.0, sg: b.1, sb: b.2)
    }

    static let blues: [Palette] = [
        make("ocean", "Ocean Blue", (0.12, 0.42, 1.0), (0.0, 0.83, 1.0)),
        make("cobalt", "Cobalt", (0.0, 0.28, 0.85), (0.35, 0.60, 1.0)),
        make("ice", "Ice Blue", (0.30, 0.65, 1.0), (0.70, 0.92, 1.0)),
        make("indigo", "Indigo", (0.35, 0.25, 1.0), (0.60, 0.55, 1.0))
    ]
    static let reds: [Palette] = [
        make("crimson", "Crimson", (0.86, 0.08, 0.20), (1.0, 0.45, 0.45)),
        make("ruby", "Ruby", (0.65, 0.05, 0.30), (1.0, 0.35, 0.60)),
        make("ember", "Ember", (1.0, 0.28, 0.12), (1.0, 0.62, 0.30))
    ]
    static let greens: [Palette] = [
        make("emerald", "Emerald", (0.05, 0.70, 0.40), (0.40, 1.0, 0.70)),
        make("forest", "Forest", (0.10, 0.50, 0.25), (0.50, 0.85, 0.45)),
        make("mint", "Mint", (0.0, 0.80, 0.65), (0.60, 1.0, 0.90))
    ]
    static let all: [Palette] = blues + reds + greens

    static func named(_ id: String) -> Palette {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Remembers which theme is selected (and keeps it between launches).
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "themeID") }
    }

    init() {
        selectedID = UserDefaults.standard.string(forKey: "themeID") ?? "ocean"
    }

    var current: Palette { Palette.named(selectedID) }
}

/// Colors used across the app. `blue` is the theme's main accent and `cyan` its lighter
/// companion, whatever the theme (the names date from the original blue-only design).
enum Theme {
    private static var palette: Palette { ThemeStore.shared.current }

    static var background: Color { palette.background }
    static var sidebar: Color { palette.sidebar }
    static var panel: Color { palette.panel }
    static var blue: Color { palette.primary }
    static var cyan: Color { palette.secondary }
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)
    static var hairline: Color { palette.primary.opacity(0.22) }

    static var gradient: LinearGradient {
        LinearGradient(colors: [palette.secondary, palette.primary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Translucent blue-tinted frame used for cards and panels.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.blue.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel(radius: CGFloat = 14) -> some View { modifier(GlassPanel(radius: radius)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.gradient))
            .foregroundStyle(.black)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.blue.opacity(configuration.isPressed ? 0.3 : 0.14)))
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .foregroundStyle(Theme.textPrimary)
    }
}
