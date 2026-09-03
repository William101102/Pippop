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

extension View {
    /// Apply to the root of **every** sheet and full-screen cover.
    ///
    /// `preferredColorScheme` sets the scheme for "this presentation" — and a
    /// sheet is its own presentation, not part of the one it was presented
    /// from. So the single call on the app's root view in `PinpopApp` covers
    /// the map and nothing else: every sheet was quietly falling back to
    /// whatever the *system* appearance was. With the phone in dark mode and
    /// the app set to Day that showed up as a dark Me sheet over a light map;
    /// with the phone in light mode and the app set to Night, the reverse.
    /// Neither had anything to do with the toggle "not taking effect" — the
    /// setting simply never reached those views.
    func themedPresentation() -> some View {
        modifier(ThemedPresentation())
    }
}

private struct ThemedPresentation: ViewModifier {
    @Environment(ThemeStore.self) private var theme

    func body(content: Content) -> some View {
        content.preferredColorScheme(theme.preference.colorScheme)
    }
}
