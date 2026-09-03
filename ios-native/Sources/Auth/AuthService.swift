import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Supabase

/// Session + profile state for the whole app.
///
/// ## App Store note (Guideline 4.8)
/// Offering **Google** sign-in makes **Sign in with Apple** mandatory — Apple
/// requires an equivalent option that limits collection to name + email and
/// lets the user hide their address. Both are implemented here. If you ever
/// drop Google and keep only email/password (your own account system), the
/// requirement no longer applies — but shipping Google without Apple is a
/// guaranteed rejection.
@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case loading
        case signedOut
        /// Authenticated but has not picked a username yet.
        case needsProfile(userId: UUID)
        case signedIn(Profile)
    }

    private(set) var state: State = .loading
    private(set) var lastError: String?

    private var currentNonce: String?

    var profile: Profile? {
        if case let .signedIn(profile) = state { return profile }
        return nil
    }

    // MARK: - Session lifecycle

    func start() async {
        do {
            let session = try await Backend.client.auth.session
            await loadProfile(for: session.user.id)
        } catch {
            state = .signedOut
        }

        // Keep state in step with token refreshes and sign-outs from anywhere.
        Task { [weak self] in
            for await change in Backend.client.auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .signedIn, .tokenRefreshed, .userUpdated:
                    if let user = change.session?.user { await self.loadProfile(for: user.id) }
                case .signedOut:
                    self.state = .signedOut
                default:
                    break
                }
            }
        }
    }

    private func loadProfile(for userId: UUID) async {
        do {
            // Decode explicitly as an array — `.value.first` gives the compiler
            // nothing to infer the response type from.
            let profiles: [Profile] = try await Backend.client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value

            state = profiles.first.map(State.signedIn) ?? .needsProfile(userId: userId)
        } catch {
            // A missing row is the "finish signup" case, not a failure.
            state = .needsProfile(userId: userId)
        }
    }

    /// The Me tab's status editor — `status_emoji` + `status_text`, the pair
    /// that shows as the little disc on your avatar and the line under your
    /// name in a friend's list. Kept separate from `updateProfile` so the
    /// name/username save path stays untouched.
    ///
    /// Port of the web app's `StatusEditor`, down to the 40-character cap and
    /// the "write a line" validation.
    func updateStatus(emoji: String, text: String) async -> String? {
        guard let userId = profile?.id else { return "Not signed in" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Write a line about what you're up to" }

        struct Update: Encodable {
            let statusEmoji: String
            let statusText: String
        }
        do {
            try await Backend.client
                .from("profiles")
                .update(Update(statusEmoji: emoji, statusText: String(trimmed.prefix(40))))
                .eq("id", value: userId)
                .execute()
            await loadProfile(for: userId)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Re-reads the signed-in profile row. `profile` is derived from `state`,
    /// which is `private(set)`, so anything that writes to `profiles` from
    /// outside this class (the avatar upload in `ProfileService`, for one)
    /// needs this to pull the new row through to the UI.
    func refreshProfile() async {
        guard let userId = profile?.id else { return }
        await loadProfile(for: userId)
    }

    func signOut() async {
        try? await Backend.client.auth.signOut()
        GIDSignIn.sharedInstance.signOut()
        state = .signedOut
    }

    /// Required by Guideline 5.1.1(v): account creation implies in-app deletion.
    /// `delete_my_account` cascades every row and drops stored avatars.
    func deleteAccount() async throws {
        try await Backend.client.rpc("delete_my_account").execute()
        try? await Backend.client.auth.signOut()
        state = .signedOut
    }

    // MARK: - Sign in with Apple

    /// Feed this into `SignInWithAppleButton(onRequest:)`.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        // Apple signs the SHA256 of the nonce; Supabase verifies against the raw one.
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        lastError = nil
        do {
            let auth = try result.get()
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                lastError = "Apple didn't return an identity token — try again."
                return
            }

            try await Backend.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            // Apple hands over the real name exactly once, on first consent.
            if let name = credential.fullName {
                let display = [name.givenName, name.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !display.isEmpty { pendingDisplayName = display }
            }
        } catch {
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = error.localizedDescription
        }
        currentNonce = nil
    }

    /// Only known on the very first Apple sign-in — used to prefill the
    /// profile-completion screen.
    private(set) var pendingDisplayName: String?

    // MARK: - Google

    func signInWithGoogle(presenting: UIViewController) async {
        lastError = nil
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
            guard let idToken = result.user.idToken?.tokenString else {
                lastError = "Google didn't return an ID token — try again."
                return
            }
            try await Backend.client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
            )
        } catch {
            let nsError = error as NSError
            // -5 is the user closing the sheet; not worth surfacing.
            if nsError.domain == kGIDSignInErrorDomain, nsError.code == -5 { return }
            lastError = error.localizedDescription
        }
    }

    // MARK: - Profile completion

    func completeProfile(username: String, displayName: String) async -> String? {
        guard case let .needsProfile(userId) = state else { return "Not signed in" }
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard handle.count >= 3 else { return "Pick an ID with at least 3 characters" }

        struct NewProfile: Encodable {
            let id: UUID
            let username: String
            let displayName: String
        }

        do {
            try await Backend.client
                .from("profiles")
                .insert(NewProfile(id: userId, username: handle, displayName: displayName))
                .execute()
            await loadProfile(for: userId)
            return nil
        } catch {
            // 23505 = unique violation on username.
            if "\(error)".contains("23505") { return "That ID is already taken — try another one" }
            return error.localizedDescription
        }
    }

    /// Edits from the Me tab — display name, status, and username. Avatar
    /// and everything Ghost-Mode-related go through their own paths
    /// (`FriendsService.setGhostMode`, avatar upload once that screen
    /// exists), so this stays a narrow, low-risk write.
    ///
    /// `username` is optional so callers that only touch name/status (none
    /// currently) don't have to pass the unchanged value; `MeView` always
    /// passes it.
    func updateProfile(displayName: String, statusText: String?, username: String? = nil) async -> String? {
        guard let userId = profile?.id else { return "Not signed in" }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Display name can't be empty" }

        do {
            // Two payload shapes rather than one with an optional `username`
            // — a Codable `nil` still encodes as JSON `null`, and PostgREST
            // would happily write that over the existing value. Only send
            // the key at all when there's actually a new username.
            if let username {
                let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard trimmed.count >= 3 else { return "Username needs at least 3 characters" }
                struct Update: Encodable {
                    let displayName: String
                    let statusText: String?
                    let username: String
                }
                try await Backend.client
                    .from("profiles")
                    .update(Update(displayName: trimmedName, statusText: statusText, username: trimmed))
                    .eq("id", value: userId)
                    .execute()
            } else {
                struct Update: Encodable {
                    let displayName: String
                    let statusText: String?
                }
                try await Backend.client
                    .from("profiles")
                    .update(Update(displayName: trimmedName, statusText: statusText))
                    .eq("id", value: userId)
                    .execute()
            }
            await loadProfile(for: userId)
            return nil
        } catch {
            // 23505 = unique violation — same rule as completeProfile.
            if "\(error)".contains("23505") { return "That username is already taken" }
            return error.localizedDescription
        }
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var byte: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
                return byte
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
