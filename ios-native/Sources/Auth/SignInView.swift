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
                            Image("google-logo")
                                .resizable().scaledToFit().frame(width: 18, height: 18)
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

extension UIApplication {
    /// GoogleSignIn needs a presenting controller; SwiftUI doesn't hand us one.
    var topViewController: UIViewController? {
        let scene = connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
