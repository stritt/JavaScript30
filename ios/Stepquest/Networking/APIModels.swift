import Foundation

// Types mirror docs/API.md (Stepquest API v1). Keep field names identical to the JSON.

struct Player: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var heroLevel: Int
    var zone: Int
    var region: String?
    var localOptIn: Bool
    var flagged: Bool
    /// ISO-8601 string; kept as text so fractional-second variations never break decoding.
    var createdAt: String?
}

struct AuthAppleRequest: Encodable, Sendable {
    var identityToken: String
    var displayName: String?
}

struct AuthDevRequest: Encodable, Sendable {
    var deviceId: String
    var displayName: String?
}

struct AuthResponse: Decodable, Sendable {
    var token: String
    var player: Player
}

struct MeResponse: Decodable, Sendable {
    var player: Player
    var week: String
    var weekSteps: Int
}

/// `PATCH /v1/me` — all fields optional; nil fields are omitted from the JSON.
struct PatchMeRequest: Encodable, Sendable {
    var displayName: String?
    var localOptIn: Bool?
    var heroLevel: Int?
    var zone: Int?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(localOptIn, forKey: .localOptIn)
        try c.encodeIfPresent(heroLevel, forKey: .heroLevel)
        try c.encodeIfPresent(zone, forKey: .zone)
    }

    enum CodingKeys: String, CodingKey { case displayName, localOptIn, heroLevel, zone }
}

struct PlayerResponse: Decodable, Sendable {
    var player: Player
}

struct StepDay: Codable, Equatable, Sendable {
    /// `YYYY-MM-DD`
    var day: String
    var steps: Int
    var flights: Int
}

struct StepsUploadRequest: Encodable, Sendable {
    var days: [StepDay]
}

struct StepsUploadResponse: Decodable, Sendable {
    var accepted: Int
}

enum BoardScope: String, CaseIterable, Identifiable, Sendable {
    case friends, local, global
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friends: "Friends"
        case .local: "Local"
        case .global: "Global"
        }
    }
}

enum BoardMetric: String, CaseIterable, Identifiable, Sendable {
    case steps, level, zone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: "Weekly Steps"
        case .level: "Hero Level"
        case .zone: "Deepest Zone"
        }
    }
}

struct BoardEntry: Decodable, Equatable, Identifiable, Sendable {
    var rank: Int
    var playerId: String
    var displayName: String
    var value: Int
    var heroLevel: Int?
    var isMe: Bool
    var id: String { playerId }
}

struct BoardMe: Decodable, Equatable, Sendable {
    var rank: Int
    var value: Int
}

struct BoardResponse: Decodable, Sendable {
    var scope: String
    var metric: String
    var week: String?
    var region: String?
    var entries: [BoardEntry]
    /// `null` when the player isn't ranked.
    var me: BoardMe?
}

struct InviteResponse: Decodable, Equatable, Sendable {
    var code: String
    var url: String
    var expiresAt: String?
}

struct AcceptInviteRequest: Encodable, Sendable {
    var code: String
}

struct FriendSummary: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var heroLevel: Int
    var zone: Int
    var weekSteps: Int
}

struct FriendResponse: Decodable, Sendable {
    var friend: FriendSummary
}

struct FriendsResponse: Decodable, Sendable {
    var friends: [FriendSummary]
}

/// `{ "error": "<code>", "message": "<human text>" }`
struct APIErrorBody: Decodable, Sendable {
    var error: String
    var message: String?
}
