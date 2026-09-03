import AuthenticationServices
import GoogleSignIn
import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            backdrop

            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.brandGradient)
                        .frame(width: 78, height: 78)
                        .overlay(Text("📍").font(.system(size: 36)))
                        .shadow(color: Theme.pink.opacity(0.3), radius: 24, y: 12)

                    Text("WELCOME TO PINPOP")
                        .font(Theme.Font.body(10, weight: .heavy))
                        .kerning(1.3)
                        .foregroundStyle(Theme.pink)

                    Text("Find your people")
                        .font(Theme.Font.display(34))
                        .foregroundStyle(Theme.ink)

                    Text("A live map of the friends who matter. You choose exactly how precisely each of them can see you.")
                        .font(Theme.Font.body(13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 2)
                }

                Spacer()

                VStack(spacing: 12) {
                    // Guideline 4.8: this must be present because Google is offered.
                    SignInWithAppleButton(.continue) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await auth.completeAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        Task {
                            guard let root = UIApplication.shared.topViewController else { return }
                            await auth.signInWithGoogle(presenting: root)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            // Official multicolor "G" mark drawn as inline vector
                            // paths — Google's branding guidelines (§"G logo")
                            // require the real asset, and this app has no asset
                            // catalog, so `Image("google-logo")` would render
                            // nothing. These are the standard 18×18 paths.
                            GoogleMark()
                                .frame(width: 18, height: 18)
                            Text("Continue with Google")
                                .font(Theme.Font.body(15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Theme.ink)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .pressable()

                    if let error = auth.lastError {
                        Text(error)
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.coral)
                            .multilineTextAlignment(.center)
                    }

                    Text("By continuing you agree to share your location only with friends you approve.")
                        .font(Theme.Font.body(10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 34)
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Circle().fill(Theme.coral.opacity(0.16)).frame(width: 320).blur(radius: 40)
                .offset(x: -120, y: -240)
            Circle().fill(Theme.violet.opacity(0.14)).frame(width: 280).blur(radius: 40)
                .offset(x: 140, y: 180)
        }
        .ignoresSafeArea()
    }
}

/// Google's official four-color "G" logo, drawn as inline vector paths on a
/// 48×48 viewBox (the standard asset from Google's branding guidelines) so it
/// needs no asset catalog and stays crisp at any size.
struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 48
            context.translateBy(x: (size.width - 48 * scale) / 2, y: (size.height - 48 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for path in [Self.blue, Self.green, Self.yellow, Self.red] {
                context.fill(path, with: .color(path.color))
            }
        }
        .accessibilityLabel("Google")
    }
}

private extension GoogleMark {
    struct ColoredPath {
        let color: Color
        let path: Path
    }

    // The four official segments, verbatim from Google's branding asset
    // (46×48 viewBox, https://developers.google.com/identity/branding-guidelines).
    static let blue = ColoredPath(color: Color(hex: 0x4285F4), path: Path { p in
        p.move(to: CGPoint(x: 45.12, y: 24.5))
        p.addCurve(to: CGPoint(x: 44.72, y: 20), control1: CGPoint(x: 45.12, y: 22.94), control2: CGPoint(x: 44.98, y: 21.44))
        p.addLine(to: CGPoint(x: 23.4, y: 20))
        p.addLine(to: CGPoint(x: 23.4, y: 28.51))
        p.addLine(to: CGPoint(x: 35.62, y: 28.51))
        p.addCurve(to: CGPoint(x: 31.09, y: 35.32), control1: CGPoint(x: 35.09, y: 31.33), control2: CGPoint(x: 33.49, y: 33.72))
        p.addLine(to: CGPoint(x: 31.09, y: 40.99))
        p.addLine(to: CGPoint(x: 38.42, y: 40.99))
        p.addCurve(to: CGPoint(x: 45.12, y: 24.5), control1: CGPoint(x: 42.71, y: 37.04), control2: CGPoint(x: 45.12, y: 31.21))
    })

    static let green = ColoredPath(color: Color(hex: 0x34A853), path: Path { p in
        p.move(to: CGPoint(x: 23.4, y: 48))
        p.addCurve(to: CGPoint(x: 38.41, y: 42.51), control1: CGPoint(x: 29.52, y: 48), control2: CGPoint(x: 34.66, y: 45.97))
        p.addLine(to: CGPoint(x: 38.41, y: 42.51))
        p.addLine(to: CGPoint(x: 31.08, y: 36.84))
        p.addLine(to: CGPoint(x: 31.09, y: 36.84))
        p.addCurve(to: CGPoint(x: 23.4, y: 38.68), control1: CGPoint(x: 29.06, y: 38.2), control2: CGPoint(x: 26.46, y: 39.01))
        p.addCurve(to: CGPoint(x: 10.71, y: 29.33), control1: CGPoint(x: 17.5, y: 38.68), control2: CGPoint(x: 10.71, y: 35.23))
        p.addLine(to: CGPoint(x: 3.15, y: 29.33))
        p.addLine(to: CGPoint(x: 3.15, y: 35.19))
        p.addCurve(to: CGPoint(x: 23.4, y: 48), control1: CGPoint(x: 6.88, y: 40.35), control2: CGPoint(x: 14.53, y: 48))
    })

    static let yellow = ColoredPath(color: Color(hex: 0xFBBC05), path: Path { p in
        p.move(to: CGPoint(x: 10.71, y: 29.66))
        p.addCurve(to: CGPoint(x: 9.99, y: 25.35), control1: CGPoint(x: 10.25, y: 28.3), control2: CGPoint(x: 9.99, y: 26.85))
        p.addCurve(to: CGPoint(x: 10.71, y: 21.04), control1: CGPoint(x: 9.99, y: 23.85), control2: CGPoint(x: 10.25, y: 22.4))
        p.addLine(to: CGPoint(x: 10.71, y: 15.18))
        p.addLine(to: CGPoint(x: 3.15, y: 15.18))
        p.addLine(to: CGPoint(x: 3.15, y: 15.18))
        p.addCurve(to: CGPoint(x: 0, y: 25.35), control1: CGPoint(x: 1.14, y: 17.62), control2: CGPoint(x: 0, y: 21.05))
        p.addCurve(to: CGPoint(x: 3.15, y: 35.52), control1: CGPoint(x: 0, y: 29.65), control2: CGPoint(x: 1.14, y: 33.08))
        p.addLine(to: CGPoint(x: 3.15, y: 35.52))
        p.addLine(to: CGPoint(x: 10.71, y: 29.66))
    })

    static let red = ColoredPath(color: Color(hex: 0xEA4335), path: Path { p in
        p.move(to: CGPoint(x: 23.4, y: 9.49))
        p.addCurve(to: CGPoint(x: 32.07, y: 12.89), control1: CGPoint(x: 26.73, y: 9.49), control2: CGPoint(x: 30.07, y: 10.89))
        p.addLine(to: CGPoint(x: 38.57, y: 6.39))
        p.addLine(to: CGPoint(x: 38.57, y: 6.39))
        p.addCurve(to: CGPoint(x: 23.4, y: 0), control1: CGPoint(x: 34.65, y: 2.43), control2: CGPoint(x: 29.51, y: 0))
        p.addCurve(to: CGPoint(x: 3.15, y: 15.18), control1: CGPoint(x: 14.53, y: 0), control2: CGPoint(x: 6.88, y: 4.84))
        p.addLine(to: CGPoint(x: 10.71, y: 29.66))
        p.addLine(to: CGPoint(x: 10.71, y: 29.66))
        p.addCurve(to: CGPoint(x: 23.4, y: 9.49), control1: CGPoint(x: 12.5, y: 19.04), control2: CGPoint(x: 17.5, y: 9.49))
    })
}

extension UIApplication {
    /// GoogleSignIn needs a presenting controller; SwiftUI doesn't hand us one.
    var topViewController: UIViewController? {
        let scene = connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
