import AppIntents
import Foundation

/// The supported way to get "tap the back of your phone" to do something.
///
/// iOS's Back Tap lives in Settings → Accessibility → Touch → Back Tap and can
/// only be bound to system actions and **Shortcuts**. Apps cannot register for
/// it directly. Exposing an App Intent means the user can pick
/// "Wave at friends" there — and the same intent shows up in Shortcuts, Siri
/// and the Action button on Pro devices for free.
///
/// Tell the user how to set it up; nobody discovers this on their own. The
/// onboarding copy lives in `BackTapSetupView`.
struct WaveAtFriendsIntent: AppIntent {
    static var title: LocalizedStringResource = "Wave at friends"
    static var description = IntentDescription(
        "Sends a wave to everyone sharing with you right now.",
        categoryName: "Pinpop"
    )

    /// Runs without bringing the app forward — the point is that a knock on the
    /// back sends a wave while the phone is still in your hand.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sent = try await SocialService.waveAtEveryone()
        Haptics.shared.play(.success)
        return .result(
            dialog: sent > 0
                ? "Waved at \(sent) friend\(sent == 1 ? "" : "s") 👋"
                : "No friends to wave at yet."
        )
    }
}

struct OpenBumpIntent: AppIntent {
    static var title: LocalizedStringResource = "Bump to meet"
    static var description = IntentDescription(
        "Opens Pinpop ready to find the friend standing next to you.",
        categoryName: "Pinpop"
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.shared.pending = .bump
        return .result()
    }
}

/// Surfaces the intents in Shortcuts and Spotlight with spoken phrases.
struct PinpopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WaveAtFriendsIntent(),
            phrases: [
                "Wave at my friends on \(.applicationName)",
                "\(.applicationName) wave",
            ],
            shortTitle: "Wave",
            systemImageName: "hand.wave.fill"
        )
        AppShortcut(
            intent: OpenBumpIntent(),
            phrases: [
                "Bump on \(.applicationName)",
                "Find a friend near me with \(.applicationName)",
            ],
            shortTitle: "Bump",
            systemImageName: "dot.radiowaves.left.and.right"
        )
    }
}

/// Lets an intent hand a destination to the running UI.
@MainActor
@Observable
final class DeepLink {
    static let shared = DeepLink()
    enum Destination { case bump }
    var pending: Destination?
    private init() {}
}
