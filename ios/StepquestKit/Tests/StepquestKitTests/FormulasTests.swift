import Foundation
import XCTest
@testable import StepquestKit

final class FormulasTests: XCTestCase {
    func testBundledFormulasDecode() throws {
        let f = try Formulas.loadBundled()
        XCTAssertEqual(f.version, 1)
        XCTAssertEqual(f.idle.baseTilesPerMinute, 1)
        XCTAssertEqual(f.idle.energyPerBonusTile, 20)
        XCTAssertEqual(f.idle.offlineCapHours, 12)
        XCTAssertEqual(f.hero.base, StatBlock(hp: 40, atk: 8, def: 2))
        XCTAssertEqual(f.hero.perLevel, StatBlock(hp: 8, atk: 2, def: 1))
        XCTAssertEqual(f.hero.maxLevel, 99)
        XCTAssertEqual(f.combat.encounterEveryTiles, 6)
        XCTAssertEqual(f.combat.defeatHealPercent, 0.5)
        XCTAssertEqual(f.stride.gateStepMultiplier, 1.5)
        XCTAssertEqual(f.stride.tiers.map(\.id), ["stroll", "march", "rush", "frenzy"])
        XCTAssertEqual(f.stride.comboBonusPerLevel, Formulas.StrideConfig.defaultComboBonusPerLevel)
        XCTAssertEqual(f.zones.map(\.id), [1, 2, 3])
        XCTAssertEqual(f.zones.map(\.palette), [.meadow, .forest, .desert])
        XCTAssertEqual(f.zones[0].gate.stepHp, 8000)
        XCTAssertEqual(f.loot.slots, [.weapon, .armor, .charm])
        XCTAssertEqual(f.loot.gateGuaranteedRarity, "rare")
        XCTAssertEqual(f.leaderboards.metrics, ["steps", "level", "zone"])
    }

    /// The bundled resource is a copy of shared/formulas.json; this fails if the two drift apart.
    func testBundledCopyMatchesSharedSourceOfTruth() throws {
        let shared = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // StepquestKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // StepquestKit
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("shared/formulas.json")
        guard FileManager.default.fileExists(atPath: shared.path) else {
            throw XCTSkip("shared/formulas.json not reachable from test bundle")
        }
        let sharedFormulas = try Formulas.decode(from: Data(contentsOf: shared))
        XCTAssertEqual(sharedFormulas, try Formulas.loadBundled(),
                       "Copy shared/formulas.json to ios/StepquestKit/Sources/StepquestKit/Resources/")
    }

    func testRoundTripEncoding() throws {
        let data = try JSONEncoder().encode(Fixtures.formulas)
        XCTAssertEqual(try Formulas.decode(from: data), Fixtures.formulas)
    }

    func testUnknownPaletteAndExtraKeysAreTolerated() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixtures.formulas)) as? [String: Any])
        var zones = try XCTUnwrap(json["zones"] as? [[String: Any]])
        zones[0]["palette"] = "volcano"
        zones[0]["newFieldFromServer"] = true
        json["zones"] = zones
        json["featureFlags"] = ["raids": false]
        let f = try Formulas.decode(from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(f.zones[0].palette, .unknown)
    }

    func testValidationRejectsBrokenConfig() throws {
        var f = Fixtures.formulas
        f.zones = []
        XCTAssertThrowsError(try f.validate())

        f = Fixtures.formulas
        f.loot.gateGuaranteedRarity = "mythic"
        XCTAssertThrowsError(try f.validate())

        f = Fixtures.formulas
        f.zones[1].monsters = []
        XCTAssertThrowsError(try f.validate())

        XCTAssertNoThrow(try Fixtures.formulas.validate())
    }

    func testZoneLookups() {
        let f = Fixtures.formulas
        XCTAssertEqual(f.zone(id: 2)?.name, "The Whispering Wood")
        XCTAssertNil(f.zone(id: 9))
        XCTAssertEqual(f.nextZone(after: 1)?.id, 2)
        XCTAssertNil(f.nextZone(after: 3))
        XCTAssertEqual(f.firstZone.id, 1)
    }
}
