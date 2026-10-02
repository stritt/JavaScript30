import AuthenticationServices
import Foundation
import Observation

/// Sign in with Apple → `POST /v1/auth/apple` → session JWT in the Keychain.
/// DEBUG builds also offer `POST /v1/auth/dev` (backend must run with `DEV_AUTH=true`).
@MainActor
@Observable
final class AuthService {
    private(set) var player: Player?
    private(set) var weekSteps: Int?
    private(set) var isWorking = false
    /// Mirrors "a session token is in the Keychain" so SwiftUI observes sign-in/out.
    private(set) var isSignedIn: Bool
    var lastError: String?
    /// The player chose to play without an account (online features hidden until they sign in).
    var playsOffline: Bool {
        didSet { UserDefaults.standard.set(playsOffline, forKey: Self.offlineKey) }
    }

    @ObservationIgnored private let api: APIClient
    private static let offlineKey = "playsOffline"
    private static let deviceIdKey = "devDeviceId"
    private static let cachedPlayerKey = "cachedPlayer"

    init(api: APIClient) {
        self.api = api
        self.playsOffline = UserDefaults.standard.bool(forKey: Self.offlineKey)
        self.isSignedIn = api.hasToken
        if let data = UserDefaults.standard.data(forKey: Self.cachedPlayerKey) {
            self.player = try? JSONDecoder().decode(Player.self, from: data)
        }
        if !api.hasToken { self.player = nil }
        api.onUnauthorized = { [weak self] in self?.signOut() }
    }

    /// Show the sign-in screen when neither signed in nor explicitly offline.
    var needsOnboarding: Bool { !isSignedIn && !playsOffline }

    // MARK: Sign in with Apple

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                lastError = error.localizedDescription
            }
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                lastError = "Apple didn't return an identity token."
                return
            }
            // Apple only sends the name on the very first authorization.
            let name = credential.fullName.flatMap {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .short, options: [])
            }.flatMap { $0.isEmpty ? nil : $0 }
            await perform { try await self.api.authApple(identityToken: identityToken, displayName: name) }
        }
    }

    // MARK: Dev login

    #if DEBUG
    func devLogin(displayName: String) async {
        let deviceId: String
        if let existing = UserDefaults.standard.string(forKey: Self.deviceIdKey) {
            deviceId = existing
        } else {
            deviceId = "ios-dev-" + UUID().uuidString.lowercased()
            UserDefaults.standard.set(deviceId, forKey: Self.deviceIdKey)
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        await perform { try await self.api.authDev(deviceId: deviceId, displayName: name.isEmpty ? nil : name) }
    }
    #endif

    // MARK: Session

    func refreshMe() async {
        guard isSignedIn else { return }
        do {
            let me = try await api.me()
            setPlayer(me.player)
            weekSteps = me.weekSteps
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func update(_ patch: PatchMeRequest) async throws {
        let player = try await api.patchMe(patch)
        setPlayer(player)
    }

    func signOut() {
        api.setToken(nil)
        isSignedIn = false
        player = nil
        weekSteps = nil
        UserDefaults.standard.removeObject(forKey: Self.cachedPlayerKey)
    }

    private func perform(_ call: @escaping () async throws -> AuthResponse) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let response = try await call()
            api.setToken(response.token)
            isSignedIn = true
            setPlayer(response.player)
            playsOffline = false
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setPlayer(_ player: Player) {
        self.player = player
        if let data = try? JSONEncoder().encode(player) {
            UserDefaults.standard.set(data, forKey: Self.cachedPlayerKey)
        }
    }
}
