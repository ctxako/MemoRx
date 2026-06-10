import SwiftUI
import AuthenticationServices
import CryptoKit

struct AuthView: View {
    @AppStorage("hasSeenAuth") private var hasSeenAuth = false
    @AppStorage("appleUserID") private var appleUserID = ""
    @AppStorage("appleGivenName") private var appleGivenName = ""

    @Environment(\.colorScheme) private var colorScheme
    @State private var authError: String?
    @State private var isSigningIn = false
    @State private var currentNonce: String?

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                brandBlock
                    .padding(.top, 24)

                Spacer()

                ctaBlock
            }
        }
    }

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MemoRx")
                .font(.system(size: 52, weight: .semibold, design: .serif))
                .kerning(0.6)
                .foregroundStyle(Color(.label))
                .minimumScaleFactor(0.85)

            Text("Your daily dose.")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.appSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var ctaBlock: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn, onRequest: { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName]
                request.nonce = Self.sha256(nonce)
            }, onCompletion: handleAppleSignIn)
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(isSigningIn)
            .opacity(isSigningIn ? 0.5 : 1)

            if isSigningIn {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            if let authError {
                Text(authError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }

            Button {
                authError = nil
                hasSeenAuth = true
            } label: {
                Text("Continue as Guest")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .padding(.top, 4)
            .disabled(isSigningIn)

            Text("Progress won't sync across devices")
                .font(.system(size: 13))
                .foregroundStyle(Color.appSecondaryText.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authError = "Sign in failed. Please try again."
                return
            }
            guard let nonce = currentNonce else {
                authError = "Sign in failed (missing nonce). Please try again."
                return
            }
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                authError = "Apple didn’t return an identity token. Please try again."
                return
            }

            let appleUser = credential.user
            let givenName = credential.fullName?.givenName ?? ""
            let familyName = credential.fullName?.familyName ?? ""
            let fullAppleName: String = {
                let parts = [givenName, familyName].filter { !$0.isEmpty }
                return parts.joined(separator: " ")
            }()
            authError = nil
            isSigningIn = true

            Task { @MainActor in
                defer { isSigningIn = false }

                // Capture any prior anonymous session UID so the server can migrate that
                // row's data onto the new Apple-derived auth.uid().
                let previousAnonId = await SupabaseManager.currentUserId()

                do {
                    try await SupabaseManager.signInWithApple(idToken: idToken, nonce: nonce)
                } catch {
                    SentryReporting.captureSupabaseError(
                        error,
                        operation: "auth.signInWithApple",
                        userId: previousAnonId
                    )
                    authError = "Couldn’t sign in with Apple: \(error.localizedDescription)"
                    return
                }

                do {
                    let outcome = try await SupabaseManager.claimAppleUser(
                        appleUserId: appleUser,
                        previousAnonId: previousAnonId
                    )
                    if case .failure(let message) = outcome {
                        SentryReporting.captureSupabaseError(
                            NSError(domain: "MemoRxAuth", code: 10, userInfo: [NSLocalizedDescriptionKey: message]),
                            operation: "auth.claimAppleUser.outcomeFailure",
                            userId: previousAnonId
                        )
                        authError = "Couldn’t link your Apple ID: \(message)"
                        return
                    }
                } catch {
                    SentryReporting.captureSupabaseError(
                        error,
                        operation: "auth.claimAppleUser",
                        userId: previousAnonId
                    )
                    authError = "Couldn’t link your Apple ID: \(error.localizedDescription)"
                    return
                }

                appleUserID = appleUser
                // Apple only sends the user's name on the FIRST sign-in.
                // On re-sign-in credential.fullName is nil → fullAppleName == "".
                // Guard prevents overwriting the previously-stored name with "".
                if !fullAppleName.isEmpty {
                    appleGivenName = fullAppleName
                }
                hasSeenAuth = true
                currentNonce = nil
                if let newUid = await SupabaseManager.currentUserId() {
                    SentryReporting.setAnonymousUser(newUid)
                }

                UserProgressService.shared.syncProfileOnly()

                // Returning users (merged from anon row, or signing in on a second device)
                // already have a profile on the server. Hydrate local state and skip the
                // onboarding flow so we don't ask them for a name they already chose.
                let hydrated = await UserProgressService.shared.hydrateFromServerIfNeeded()
                if hydrated {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                }

                if let uid = await SupabaseManager.currentUserId() {
                    if let isLifetime = await SupabaseManager.fetchIsLifetime(userId: uid) {
                        UserDefaults.standard.set(isLifetime, forKey: "isLifetime")
                        await SubscriptionManager.shared.applyServerLifetimeGrant(isLifetime)
                    } else {
                        await SubscriptionManager.shared.refreshEntitlements()
                    }
                } else {
                    await SubscriptionManager.shared.refreshEntitlements()
                }
            }

        case .failure(let error):
            // ASAuthorizationError code 1001 = user canceled — don't show as an error.
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.canceled.rawValue {
                authError = nil
            } else {
                authError = error.localizedDescription
            }
        }
    }

    // MARK: - Nonce helpers (Apple-recommended pattern)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                // SecRandom failure is exceptionally rare. Use raw UUID v4 bytes
                // (~122-bit randomness) rather than the formatted string whose
                // fixed version/variant nibbles reduce effective entropy.
                let u = UUID().uuid
                randoms = [u.0,  u.1,  u.2,  u.3,  u.4,  u.5,  u.6,  u.7,
                           u.8,  u.9,  u.10, u.11, u.12, u.13, u.14, u.15]
            }
            for random in randoms where remainingLength > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    AuthView()
}
