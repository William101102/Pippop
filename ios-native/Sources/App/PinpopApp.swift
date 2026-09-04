import GoogleSignIn
import SwiftUI

@main
struct PinpopApp: App {
    @State private var auth = AuthService()
    @State private var location = LocationService()
    @State private var motion = MotionActivityService()
    @State private var theme = ThemeStore()
    /// A singleton rather than `@State`, because `LocationService` has to
    /// reach it from a background relaunch where no view exists.
    private let autoStatus = AutoStatusService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(location)
                .environment(motion)
                .environment(autoStatus)
                .environment(theme)
                .tint(Theme.violet)
                // This used to be pinned to `.light`, because every surface
                // was a hardcoded light value with no dark counterpart — so
                // a device in Dark Mode got system-drawn text (TextField
                // input especially) in white on our hardcoded-white cards.
                // Every token in `Theme` is now a dynamic colour with both
                // palettes from `styles.css`, so the app can follow the
                // system again — or be pinned to Day/Night from the map's
                // theme button, exactly like the web app's toggle.
                .preferredColorScheme(theme.preference.colorScheme)
                .task {
                    // All of these have to happen at *app* level, not on the
                    // map screen: iOS relaunches this app in the background
                    // for a significant location change or a visit, and on
                    // that launch no view ever appears to kick things off.
                    location.resume()
                    motion.start()
                    autoStatus.start()
                    await auth.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Being in the app is the clearest possible "awake", and
                    // it's also the clock AutoStatusService measures idleness
                    // from — see its note on why iOS can't tell an app
                    // whether the *phone* is being used.
                    if phase == .active { autoStatus.noteAppActive() }
                }
                .onOpenURL { url in
                    // Google's OAuth callback, plus pinpop:// invite links.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    InviteRouter.handle(url)
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ZStack {
                    Theme.ground.ignoresSafeArea()
                    ProgressView().tint(Theme.violet)
                }
            case .signedOut:
                SignInView()
            case .needsProfile:
                CompleteProfileView()
            case .signedIn:
                MapScreen()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.state)
    }
}

struct CompleteProfileView: View {
    @Environment(AuthService.self) private var auth
    @State private var username = ""
    @State private var displayName = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Almost there")
                    .font(Theme.Font.display(30))
                    .foregroundStyle(Theme.ink)
                Text("Pick the handle friends will find you by.")
                    .font(Theme.Font.body(13, weight: .medium))
                    .foregroundStyle(Theme.muted)

                field("Display name", text: $displayName)
                field("Username", text: $username)
                    .textInputAutocapitalization(.never)

                if let error {
                    Text(error)
                        .font(Theme.Font.body(11, weight: .medium))
                        .foregroundStyle(Theme.coral)
                }

                Button {
                    Task {
                        busy = true
                        error = await auth.completeProfile(
                            username: username,
                            displayName: displayName.isEmpty ? username : displayName
                        )
                        busy = false
                    }
                } label: {
                    Text(busy ? "Saving…" : "Start using Pinpop")
                        .font(Theme.Font.body(15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(busy || username.count < 3)
                .pressable()
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            if displayName.isEmpty, let suggested = auth.pendingDisplayName {
                displayName = suggested
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(Theme.Font.body(15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .tint(Theme.violet)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .autocorrectionDisabled()
    }
}

/// `pinpop://add/<username>` and `?t=<token>` links, matching the web app's
/// invite semantics in `src/lib/geo.ts`.
///
/// Routes to Explore with the username prefilled. Actually *creating* the
/// friendship from a redeemed token is still a stub on the Explore screen —
/// see the doc comment on `ExploreView` for why.
enum InviteRouter {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "pinpop", url.host == "add" else { return }
        let username = url.pathComponents
            .first { $0 != "/" }
            ?? url.lastPathComponent
        guard !username.isEmpty else { return }
        DeepLink.shared.pending = .addFriend(username: username)
    }
}
