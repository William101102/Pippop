import SwiftUI

/// The web app's design tokens, ported so the native build reads as the same
/// product. Values mirror `src/styles.css` `:root` — keep them in sync.
enum Theme {
    static let coral = Color(hex: 0xFF6847)
    static let pink = Color(hex: 0xFF3F8E)
    static let violet = Color(hex: 0x5B35F2)
    static let yellow = Color(hex: 0xFFD34E)
    static let ink = Color(hex: 0x281F42)
    /// Already the contrast-corrected value (AA on the light ground).
    static let muted = Color(hex: 0x5F5670)
    static let ground = Color(hex: 0xFFF8EF)
    static let surface = Color.white

    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFF7B42), Color(hex: 0xFF3E86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Radius {
        static let card: CGFloat = 32
        static let row: CGFloat = 18
        static let chip: CGFloat = 20
    }

    enum Font {
        // Fredoka/DM Sans ship as bundled files in a later pass; rounded system
        // is the closest stand-in and keeps the playful tone.
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }
    }
}

// `Color(hex:)` lives in Sources/Shared/ColorHex.swift — it is compiled into
// the widget extension too, so it must not be duplicated here.

/// The soft floating card used for sheets, the dock and the person card.
struct FloatingCard: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    func body(content: Content) -> some View {
        content
            .background(Theme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white, lineWidth: 2)
            )
            .shadow(color: Color(hex: 0x2C1E48).opacity(0.28), radius: 30, x: 0, y: 18)
    }
}

extension View {
    func floatingCard(radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(FloatingCard(radius: radius))
    }

    /// Uniform press feedback, matching the `:active` scale added on the web.
    func pressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(PressableStyle(scale: scale))
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
