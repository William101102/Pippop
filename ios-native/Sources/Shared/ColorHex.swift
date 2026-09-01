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
