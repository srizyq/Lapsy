import Foundation
import Observation
import AuthenticationServices
import CryptoKit

struct AuthUser: Codable, Equatable {
    var id: String
    var email: String?
}

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    var user: AuthUser
}

struct Profile: Codable, Equatable {
    var id: String
    var displayName: String?
    var avatarUrl: String?
    var units: String = "metric"
    var weightKg: Double?
    var heightCm: Double?
    var birthYear: Int?

    var isMetric: Bool { units == "metric" }
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Double?
    var expiresAt: Double?
    var user: AuthUser
}

private struct ProfileUpdate: Encodable {
    var displayName: String?
    var units: String
    var weightKg: Double?
    var heightCm: Double?
    var birthYear: Int?
}

/// Who is signed in, their session and their profile. Talks to Supabase over REST.
@MainActor @Observable
final class AccountStore {
    enum State { case loading, signedOut, signedIn }

    private(set) var state: State = .loading
    private(set) var user: AuthUser?
    private(set) var profile: Profile?
    private(set) var busy = false
    var errorMessage: String?
    var notice: String?

    @ObservationIgnored private let api = SupabaseAPI()
    @ObservationIgnored private var session: AuthSession?
    @ObservationIgnored private var appleNonce: String?
    @ObservationIgnored private let keychainAccount = "session"
    @ObservationIgnored private let webAuth = WebAuthRunner()

    // MARK: - Launch

    /// Restores a saved session, refreshing it if it is about to expire.
    func restore() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LAPSY_SKIP_AUTH"] == "1" {
            state = .signedIn
            return
        }
        if ProcessInfo.processInfo.environment["LAPSY_FORCE_SIGNED_OUT"] == "1" {
            state = .signedOut
            return
        }
        #endif
        guard let data = Keychain.load(account: keychainAccount),
              let saved = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            state = .signedOut
            return
        }
        session = saved
        user = saved.user
        state = .signedIn
        do {
            try await refreshIfNeeded()
            await loadProfile()
        } catch let error as APIError where error.status == 400 || error.status == 401 {
            // Refresh token no longer valid: sign in again.
            clearSession()
        } catch {
            // Offline: stay signed in with what we have.
            await loadProfile()
        }
    }

    // MARK: - Email

    func signIn(email: String, password: String) async {
        await run {
            let data = try await self.api.send(
                "auth/v1/token", method: "POST", query: ["grant_type": "password"],
                body: ["email": email, "password": password]
            )
            try self.adopt(data)
        }
    }

    func signUp(email: String, password: String, name: String) async {
        await run {
            let data = try await self.api.send(
                "auth/v1/signup", method: "POST",
                body: SignUpBody(email: email, password: password, data: ["full_name": name])
            )
            // With email confirmation on, there is no session yet.
            if let tokens = try? Self.decoder.decode(TokenResponse.self, from: data) {
                try self.adopt(tokens)
            } else {
                self.notice = "Check your email for a link to confirm your account, then sign in."
            }
        }
    }

    func sendPasswordReset(email: String) async {
        guard !email.isEmpty else {
            errorMessage = "Type your email first."
            return
        }
        await run {
            _ = try await self.api.send("auth/v1/recover", method: "POST", body: ["email": email])
            self.notice = "If that email has an account, a reset link is on its way."
        }
    }

    // MARK: - Apple

    /// Call from the Apple button's request closure.
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple sign in didn't finish. Try again."
            }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                errorMessage = "Apple sign in didn't return what we need."
                return
            }
            // Apple only sends the name the very first time.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            await run {
                let data = try await self.api.send(
                    "auth/v1/token", method: "POST", query: ["grant_type": "id_token"],
                    body: IDTokenBody(provider: "apple", idToken: idToken, nonce: nonce)
                )
                try self.adopt(data)
                if !name.isEmpty, self.profile?.displayName?.isEmpty ?? true {
                    var edited = self.profile
                    edited?.displayName = name
                    if let edited { try await self.saveProfile(edited) }
                }
            }
        }
    }

    // MARK: - Google (web sign in; no SDK)

    func signInWithGoogle() async {
        await run {
            var components = URLComponents(url: URL(string: Secrets.supabaseURL)!.appending(path: "auth/v1/authorize"),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "provider", value: "google"),
                URLQueryItem(name: "redirect_to", value: "lapsy://auth-callback"),
            ]
            guard let callback = try await self.webAuth.start(url: components.url!, scheme: "lapsy") else { return }
            // Tokens come back in the URL fragment.
            var pairs: [String: String] = [:]
            for item in (callback.fragment ?? "").split(separator: "&") {
                let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { pairs[parts[0]] = parts[1].removingPercentEncoding ?? parts[1] }
            }
            guard let access = pairs["access_token"], let refresh = pairs["refresh_token"] else {
                throw APIError(status: 0, message: "Google sign in didn't finish. Try again.")
            }
            let userData = try await self.api.send("auth/v1/user", token: access)
            let user = try Self.decoder.decode(AuthUser.self, from: userData)
            let expiresIn = Double(pairs["expires_in"] ?? "") ?? 3600
            try self.adopt(AuthSession(accessToken: access, refreshToken: refresh,
                                       expiresAt: Date().timeIntervalSince1970 + expiresIn, user: user))
        }
    }

    // MARK: - Profile

    func loadProfile() async {
        guard let id = user?.id else { return }
        do {
            let data = try await authorized("rest/v1/profiles", query: ["id": "eq.\(id)", "select": "*"])
            if let found = try Self.decoder.decode([Profile].self, from: data).first {
                profile = found
            } else {
                // Account made before the sign-up trigger existed: create the row now.
                let created = try await authorized(
                    "rest/v1/profiles", method: "POST", body: ["id": id],
                    headers: ["Prefer": "return=representation"]
                )
                profile = try Self.decoder.decode([Profile].self, from: created).first
            }
        } catch {
            // Keep any cached profile; the Profile screen shows its own retry state.
            if profile == nil { errorMessage = (error as? APIError)?.message }
        }
    }

    func saveProfile(_ edited: Profile) async throws {
        guard let id = user?.id else { return }
        let update = ProfileUpdate(displayName: edited.displayName, units: edited.units,
                                   weightKg: edited.weightKg, heightCm: edited.heightCm,
                                   birthYear: edited.birthYear)
        let data = try await authorized(
            "rest/v1/profiles", method: "PATCH", query: ["id": "eq.\(id)"], body: update,
            headers: ["Prefer": "return=representation"]
        )
        if let saved = try Self.decoder.decode([Profile].self, from: data).first { profile = saved }
    }

    // MARK: - Sign out / delete

    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await api.send("auth/v1/logout", method: "POST", token: token)
        }
        clearSession()
    }

    /// Permanently deletes the account and all its data (server-side function).
    func deleteAccount() async -> Bool {
        busy = true
        defer { busy = false }
        do {
            _ = try await authorized("rest/v1/rpc/delete_my_account", method: "POST", body: [String: String]())
            clearSession()
            return true
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Couldn't delete the account. Try again."
            return false
        }
    }

    // MARK: - Plumbing

    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        errorMessage = nil
        notice = nil
        defer { busy = false }
        do { try await work() } catch {
            errorMessage = (error as? APIError)?.message ?? "Something went wrong. Try again."
        }
    }

    private func adopt(_ data: Data) throws {
        try adopt(Self.decoder.decode(TokenResponse.self, from: data))
    }

    private func adopt(_ tokens: TokenResponse) throws {
        let expires = tokens.expiresAt ?? (Date().timeIntervalSince1970 + (tokens.expiresIn ?? 3600))
        try adopt(AuthSession(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
                              expiresAt: expires, user: tokens.user))
    }

    private func adopt(_ new: AuthSession) throws {
        session = new
        user = new.user
        state = .signedIn
        if let data = try? JSONEncoder().encode(new) { Keychain.save(data, account: keychainAccount) }
        Task { await loadProfile() }
    }

    private func clearSession() {
        session = nil
        user = nil
        profile = nil
        Keychain.delete(account: keychainAccount)
        state = .signedOut
    }

    private func refreshIfNeeded() async throws {
        guard let current = session else { return }
        guard current.expiresAt - Date().timeIntervalSince1970 < 60 else { return }
        let data = try await api.send(
            "auth/v1/token", method: "POST", query: ["grant_type": "refresh_token"],
            body: ["refresh_token": current.refreshToken]
        )
        try adopt(data)
    }

    private func authorized(
        _ path: String, method: String = "GET", query: [String: String] = [:],
        body: Encodable? = nil, headers: [String: String] = [:]
    ) async throws -> Data {
        try await refreshIfNeeded()
        guard let token = session?.accessToken else { throw APIError(status: 401, message: "Please sign in again.") }
        return try await api.send(path, method: method, query: query, body: body, token: token, headers: headers)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct SignUpBody: Encodable {
    var email: String
    var password: String
    var data: [String: String]
}

private struct IDTokenBody: Encodable {
    var provider: String
    var idToken: String
    var nonce: String
}

/// Runs the system web sign-in sheet and returns the redirect URL.
@MainActor
final class WebAuthRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    func start(url: URL, scheme: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: callback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
