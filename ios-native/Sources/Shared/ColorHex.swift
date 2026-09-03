import SwiftUI

/// Compiled into both the app and the widget extension, so the brand colours
/// are defined once. Keep this file free of app-only dependencies.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Parses the `profiles.avatar_color` strings the web app stores —
    /// `"#ff6658"`, or the same six digits without the hash. Returns nil for
    /// anything it can't read, so callers can fall back to the brand colour
    /// the same way `.avatar-photo { --avatar-color: var(--coral) }` does.
    init?(hexString: String?) {
        guard var raw = hexString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        // Allow the #rgb shorthand by expanding each digit.
        if raw.count == 3 { raw = raw.map { "\($0)\($0)" }.joined() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

/// Brand values the widget needs without pulling in the app's Theme.
enum Brand {
    static let coral = Color(hex: 0xFF6847)
    static let pink = Color(hex: 0xFF3F8E)
    static let violet = Color(hex: 0x5B35F2)
    static let night = Color(hex: 0x1B1430)

    static let gradient = LinearGradient(
        colors: [Color(hex: 0xFF7B42), Color(hex: 0xFF3E86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
