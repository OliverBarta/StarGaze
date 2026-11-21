//
//  AuthService.swift
//  StarGaze
//

import Auth0
import Foundation
import Observation

/// Wraps Auth0.swift (3.x) for login, sign-up, logout and session restore.
/// Credentials live only in the Keychain, through `CredentialsManager`.
@Observable
final class AuthService {
    private(set) var user: AppUser?
    /// True while the saved session is being restored at launch.
    private(set) var isLoading = true
    /// True while the Auth0 login page is open.
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?

    private let credentialsManager = CredentialsManager(authentication: Auth0.authentication())
    @ObservationIgnored private var hasRestored = false

    /// Must match the Allowed Callback and Logout URLs in the Auth0 dashboard exactly.
    /// Set explicitly because Auth0.swift's default uses the bundle ID's original casing for the scheme.
    private static let callbackURL = URL(string: "com.oliver.stargaze://dev-egzorfokrbjlmaxi.us.auth0.com/ios/com.oliver.StarGaze/callback")!
    private static let scope = "openid profile email offline_access"
    /// The Auth0 API identifier. With an audience, Auth0 issues a JWT access token that
    /// Supabase (Third-Party Auth) can verify; without one the token is opaque.
    private static let apiAudience = "https://stargaze-api"

    func restoreSession() async {
        guard !hasRestored else { return }
        hasRestored = true
        defer { isLoading = false }

        guard credentialsManager.canRenew() else { return }
        do {
            _ = try await credentialsManager.credentials()
            user = storedUser()
        } catch let error as CredentialsManagerError where Self.isSessionInvalid(error) {
            try? credentialsManager.clear()
            user = nil
        } catch {
            // Most likely offline. Keep the user signed in with the stored credentials;
            // they'll be renewed the next time credentials are requested online.
            user = storedUser()
        }
    }

    /// A current Auth0 access token for Supabase, renewed through the refresh token if it expired.
    func accessToken() async throws -> String {
        try await credentialsManager.credentials().accessToken
    }

    func login() async {
        await authenticate(signUp: false)
    }

    func signUp() async {
        await authenticate(signUp: true)
    }

    func logout() async {
        errorMessage = nil
        do {
            try await Auth0.webAuth()
                .redirectURL(Self.callbackURL)
                .logout()
        } catch WebAuthError.userCancelled {
            // The user dismissed the system prompt, so stay signed in.
            return
        } catch {
            // Couldn't end the Auth0 browser session (e.g. offline). Still sign out on this device.
        }
        try? credentialsManager.clear()
        user = nil
    }

    private func authenticate(signUp: Bool) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        var webAuth = Auth0.webAuth()
            .redirectURL(Self.callbackURL)
            .scope(Self.scope)
            .audience(Self.apiAudience)
        if signUp {
            webAuth = webAuth.parameters(["screen_hint": "signup"])
        }

        do {
            let credentials = try await webAuth.start()
            try credentialsManager.store(credentials: credentials)
            user = storedUser()
        } catch WebAuthError.userCancelled {
            errorMessage = "Login was cancelled. Tap Log In to try again."
        } catch {
            errorMessage = "Couldn't log in. Check your connection and try again."
        }
    }

    private func storedUser() -> AppUser? {
        (try? credentialsManager.userProfile()).map { AppUser(profile: $0) }
    }

    /// True only when the session can never be renewed (revoked or invalid refresh token,
    /// deleted user, expired session), not for network or other transient failures.
    private static func isSessionInvalid(_ error: CredentialsManagerError) -> Bool {
        switch error {
        case .noCredentials, .noRefreshToken, .sessionExpired:
            return true
        case .renewFailed:
            guard let cause = error.cause as? AuthenticationError else { return false }
            return cause.isInvalidRefreshToken || cause.isRefreshTokenDeleted
        default:
            return false
        }
    }
}

#if DEBUG
extension AuthService {
    /// A service in a fixed state for previews. It never talks to Auth0.
    static func preview(user: AppUser?, isLoading: Bool = false, errorMessage: String? = nil) -> AuthService {
        let service = AuthService()
        service.hasRestored = true
        service.user = user
        service.isLoading = isLoading
        service.errorMessage = errorMessage
        return service
    }
}
#endif
