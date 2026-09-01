import GoogleSignIn
import SwiftUI

@main
struct PinpopApp: App {
    @State private var auth = AuthService()
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(location)
                .tint(Theme.violet)
                .task { await auth.start() }
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
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .autocorrectionDisabled()
    }
}

/// `pinpop://add/<username>` and `?t=<token>` links, matching the web app's
/// invite semantics in `src/lib/geo.ts`.
enum InviteRouter {
    static func handle(_ url: URL) {
        guard url.scheme == "pinpop" else { return }
        // Wire into the friends flow once that screen exists.
    }
}
