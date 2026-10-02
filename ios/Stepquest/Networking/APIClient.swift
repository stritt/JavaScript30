import Foundation

enum APIError: Error, LocalizedError, Equatable {
    /// Non-2xx with the server's `{ error, message }` body when present.
    case server(status: Int, code: String, message: String?)
    case unauthorized
    case notSignedIn
    case invalidResponse
    case decoding(String)
    case transport(String)

    var code: String? {
        if case let .server(_, code, _) = self { return code }
        return nil
    }

    var status: Int? {
        switch self {
        case let .server(status, _, _): status
        case .unauthorized: 401
        default: nil
        }
    }

    var errorDescription: String? {
        switch self {
        case let .server(status, code, message): message ?? "Server error \(status) (\(code))"
        case .unauthorized: "Your session expired. Please sign in again."
        case .notSignedIn: "Sign in to use online features."
        case .invalidResponse: "Unexpected response from the server."
        case let .decoding(detail): "Couldn't read the server response. \(detail)"
        case let .transport(detail): "Network problem: \(detail)"
        }
    }

    /// `409 local_opt_in_required` from `GET /v1/boards/local`. (The backend also sends
    /// `409 region_unknown` there, which is a plain error, not an opt-in prompt.)
    var isLocalOptInRequired: Bool { code == "local_opt_in_required" }
}

/// Where the API lives. Debug defaults to `http://localhost:8787` (wrangler dev), Release to production,
/// both via the `StepquestAPIBaseURL` Info.plist key; DEBUG builds can override it in Settings.
enum AppConfig {
    static let overrideKey = "apiBaseURLOverride"
    static let productionURL = URL(string: "https://api.stepquest.app")!

    static var apiBaseURL: URL {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), url.scheme != nil {
            return url
        }
        #endif
        if let raw = Bundle.main.object(forInfoDictionaryKey: "StepquestAPIBaseURL") as? String,
           !raw.isEmpty, !raw.hasPrefix("$("), let url = URL(string: raw) {
            return url
        }
        return productionURL
    }
}

/// Async/await client for docs/API.md. The session token lives in the Keychain (`TokenStore`).
@MainActor
final class APIClient {
    var baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Called when the server rejects the token (401) so the app can sign out.
    var onUnauthorized: (@MainActor () -> Void)?

    init(baseURL: URL = AppConfig.apiBaseURL, tokenStore: TokenStore = KeychainTokenStore(), session: URLSession? = nil) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: config)
        }
    }

    var hasToken: Bool { tokenStore.token != nil }

    func setToken(_ token: String?) { tokenStore.token = token }

    // MARK: Auth

    func authApple(identityToken: String, displayName: String?) async throws -> AuthResponse {
        try await send("POST", "/v1/auth/apple", body: AuthAppleRequest(identityToken: identityToken, displayName: displayName), authenticated: false)
    }

    func authDev(deviceId: String, displayName: String?) async throws -> AuthResponse {
        try await send("POST", "/v1/auth/dev", body: AuthDevRequest(deviceId: deviceId, displayName: displayName), authenticated: false)
    }

    // MARK: Player

    func me() async throws -> MeResponse {
        try await send("GET", "/v1/me")
    }

    func patchMe(_ patch: PatchMeRequest) async throws -> Player {
        let response: PlayerResponse = try await send("PATCH", "/v1/me", body: patch)
        return response.player
    }

    // MARK: Steps

    @discardableResult
    func uploadSteps(_ days: [StepDay]) async throws -> Int {
        guard !days.isEmpty else { return 0 }
        let response: StepsUploadResponse = try await send("POST", "/v1/steps", body: StepsUploadRequest(days: days))
        return response.accepted
    }

    // MARK: Boards

    func board(scope: BoardScope, metric: BoardMetric) async throws -> BoardResponse {
        try await send("GET", "/v1/boards/\(scope.rawValue)", query: [URLQueryItem(name: "metric", value: metric.rawValue)])
    }

    // MARK: Friends

    func createInvite() async throws -> InviteResponse {
        try await send("POST", "/v1/friends/invite", body: EmptyBody())
    }

    func acceptInvite(code: String) async throws -> FriendSummary {
        let response: FriendResponse = try await send("POST", "/v1/friends/accept", body: AcceptInviteRequest(code: code))
        return response.friend
    }

    func friends() async throws -> [FriendSummary] {
        let response: FriendsResponse = try await send("GET", "/v1/friends")
        return response.friends
    }

    func removeFriend(playerId: String) async throws {
        _ = try await sendRaw("DELETE", "/v1/friends/\(playerId)", body: Optional<EmptyBody>.none, query: [], authenticated: true)
    }

    // MARK: Config

    /// Raw `GET /v1/config` body (formulas.json). Public route.
    func configData() async throws -> Data {
        try await sendRaw("GET", "/v1/config", body: Optional<EmptyBody>.none, query: [], authenticated: false)
    }

    // MARK: Plumbing

    struct EmptyBody: Encodable {}

    private func send<T: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], authenticated: Bool = true
    ) async throws -> T {
        try await send(method, path, body: Optional<EmptyBody>.none, query: query, authenticated: authenticated)
    }

    private func send<T: Decodable, B: Encodable>(
        _ method: String, _ path: String, body: B?, query: [URLQueryItem] = [], authenticated: Bool = true
    ) async throws -> T {
        let data = try await sendRaw(method, path, body: body, query: query, authenticated: authenticated)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func sendRaw<B: Encodable>(
        _ method: String, _ path: String, body: B?, query: [URLQueryItem], authenticated: Bool
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let token = tokenStore.token else { throw APIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 && authenticated {
                onUnauthorized?()
                throw APIError.unauthorized
            }
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.server(status: http.statusCode, code: body?.error ?? "http_\(http.statusCode)", message: body?.message)
        }
        return data
    }
}
