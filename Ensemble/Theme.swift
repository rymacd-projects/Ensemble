import SwiftUI

/// Black and blue palette used across the whole app.
enum Theme {
    static let background = Color(red: 0.012, green: 0.012, blue: 0.027)
    static let sidebar = Color(red: 0.02, green: 0.025, blue: 0.05)
    static let panel = Color(red: 0.04, green: 0.06, blue: 0.12)
    static let blue = Color(red: 0.12, green: 0.42, blue: 1.0)
    static let cyan = Color(red: 0.0, green: 0.83, blue: 1.0)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)
    static let hairline = Color(red: 0.12, green: 0.42, blue: 1.0).opacity(0.22)

    static let gradient = LinearGradient(colors: [cyan, blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
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
