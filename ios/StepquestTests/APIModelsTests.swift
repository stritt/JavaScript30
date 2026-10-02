import XCTest
@testable import Stepquest

/// Decodes the exact sample payloads from docs/API.md so client types stay in sync with the contract.
final class APIModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testAuthResponse() throws {
        let json = """
        { "token": "jwt.token.here", "player": {
            "id": "p_123", "displayName": "Brandon", "heroLevel": 7, "zone": 2,
            "region": "US-CA-San Francisco", "localOptIn": true, "flagged": false,
            "createdAt": "2026-10-02T12:00:00Z" } }
        """
        let response = try decoder.decode(AuthResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.token, "jwt.token.here")
        XCTAssertEqual(response.player.heroLevel, 7)
        XCTAssertEqual(response.player.region, "US-CA-San Francisco")
        XCTAssertTrue(response.player.localOptIn)
    }

    func testPlayerWithNullRegion() throws {
        let json = """
        { "id": "p_1", "displayName": "A", "heroLevel": 1, "zone": 1, "region": null,
          "localOptIn": false, "flagged": false, "createdAt": "2026-10-02T12:00:00.123Z" }
        """
        let player = try decoder.decode(Player.self, from: Data(json.utf8))
        XCTAssertNil(player.region)
    }

    func testMeResponse() throws {
        let json = """
        { "player": { "id": "p_1", "displayName": "A", "heroLevel": 3, "zone": 1, "region": null,
          "localOptIn": false, "flagged": false, "createdAt": "2026-10-02T12:00:00Z" },
          "week": "2026-W40", "weekSteps": 41234 }
        """
        let me = try decoder.decode(MeResponse.self, from: Data(json.utf8))
        XCTAssertEqual(me.week, "2026-W40")
        XCTAssertEqual(me.weekSteps, 41234)
    }

    func testBoardResponseWithMeAndNullMe() throws {
        let json = """
        { "scope": "local", "metric": "steps", "week": "2026-W40", "region": "US-CA-San Francisco",
          "entries": [ { "rank": 1, "playerId": "p_9", "displayName": "Ava", "value": 70211, "heroLevel": 14, "isMe": false } ],
          "me": { "rank": 12, "value": 41234 } }
        """
        let board = try decoder.decode(BoardResponse.self, from: Data(json.utf8))
        XCTAssertEqual(board.entries.first?.displayName, "Ava")
        XCTAssertEqual(board.me, BoardMe(rank: 12, value: 41234))

        let unranked = """
        { "scope": "global", "metric": "level", "week": "2026-W40", "region": null, "entries": [], "me": null }
        """
        XCTAssertNil(try decoder.decode(BoardResponse.self, from: Data(unranked.utf8)).me)
    }

    func testFriends() throws {
        let invite = try decoder.decode(InviteResponse.self, from: Data("""
        { "code": "K7QF2M", "url": "https://stepquest.app/i/K7QF2M", "expiresAt": "2026-10-09T12:00:00Z" }
        """.utf8))
        XCTAssertEqual(invite.code, "K7QF2M")
        let friends = try decoder.decode(FriendsResponse.self, from: Data("""
        { "friends": [ { "id": "p_2", "displayName": "Kai", "heroLevel": 5, "zone": 1, "weekSteps": 12000 } ] }
        """.utf8))
        XCTAssertEqual(friends.friends.first?.weekSteps, 12000)
    }

    func testPatchMeOmitsNilFields() throws {
        let data = try JSONEncoder().encode(PatchMeRequest(heroLevel: 8, zone: 2))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["heroLevel", "zone"])
    }

    func testStepsUploadShape() throws {
        let body = StepsUploadRequest(days: [StepDay(day: "2026-10-01", steps: 8123, flights: 4)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        let days = try XCTUnwrap(object["days"] as? [[String: Any]])
        XCTAssertEqual(days.first?["day"] as? String, "2026-10-01")
        XCTAssertEqual(days.first?["steps"] as? Int, 8123)
    }

    func testErrorBodyAndLocalOptIn() throws {
        let body = try decoder.decode(APIErrorBody.self, from: Data("""
        { "error": "local_opt_in_required", "message": "Opt in first" }
        """.utf8))
        let error = APIError.server(status: 409, code: body.error, message: body.message)
        XCTAssertTrue(error.isLocalOptInRequired)
        XCTAssertFalse(APIError.server(status: 400, code: "bad_request", message: nil).isLocalOptInRequired)
        XCTAssertFalse(APIError.server(status: 409, code: "region_unknown", message: nil).isLocalOptInRequired)
        XCTAssertEqual(APIError.server(status: 409, code: "region_unknown", message: "No region yet").errorDescription, "No region yet")
    }
}
