import SwiftUI

/// Day / night / auto — a port of `src/lib/theme.ts`.
///
/// The stored value is the user's *preference*; what actually gets applied is
/// the resolved scheme. "Auto" resolves to nil, which is SwiftUI's way of
/// saying "follow the system", so the OS does the resolving the web app has
/// to do by hand with `matchMedia`.
enum ThemePreference: String, CaseIterable, Sendable {
    /// Declaration order is also the order the Appearance picker lays the
    /// tiles out — Day, Night, Auto. The raw values are unchanged, so a
    /// preference saved before this reorder still reads back correctly.
    case light, dark, auto

    /// Matches the web app's `THEME_LABEL`.
    var label: String {
        switch self {
        case .auto: "Auto"
        case .light: "Day"
        case .dark: "Night"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// `THEME_CYCLE` — auto → light → dark → auto.
    var next: ThemePreference {
        switch self {
        case .auto: .light
        case .light: .dark
        case .dark: .auto
        }
    }
}

@MainActor
@Observable
final class ThemeStore {
    /// Same UserDefaults key as the web app's localStorage key, so the two
    /// stay recognisably the same setting.
    private static let key = "pinpop-theme"

    var preference: ThemePreference {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: Self.key) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        preference = stored.flatMap(ThemePreference.init(rawValue:)) ?? .auto
    }

    func cycle() {
        preference = preference.next
    }
}
