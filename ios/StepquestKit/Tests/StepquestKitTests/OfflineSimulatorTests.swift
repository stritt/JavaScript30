import Foundation
import XCTest
@testable import StepquestKit

final class OfflineSimulatorTests: XCTestCase {
    let f = Fixtures.formulas
    lazy var sim = OfflineSimulator(formulas: f)

    func testBaseTrickleWithZeroSteps() {
        var state = Fixtures.newGame()
        let s = sim.advance(&state, elapsed: 10 * 60, newSteps: 0, now: Fixtures.t0)
        XCTAssertEqual(s.tilesWalked, 10, accuracy: 1e-6)
        XCTAssertEqual(s.bonusTiles, 0)
        XCTAssertEqual(s.encounters, 1, "one encounter every 6 tiles")
        XCTAssertEqual(s.kills + s.defeats, s.encounters)
        XCTAssertEqual(state.trail.frontierTile, 10, accuracy: 1e-6)
        XCTAssertEqual(state.trail.encounterProgress, 4, accuracy: 1e-6)
        XCTAssertEqual(state.lastSimulatedAt, Fixtures.t0)
    }

    func testStepsBecomeBonusTiles() {
        var state = Fixtures.newGame()
        // 2000 steps * 1 energy / 20 energy per tile = 100 bonus tiles, no elapsed time.
        let s = sim.advance(&state, elapsed: 0, newSteps: 2000, now: Fixtures.t0)
        XCTAssertEqual(s.bonusTiles, 100, accuracy: 1e-6)
        XCTAssertEqual(s.tilesWalked, 100, accuracy: 1e-6)
        XCTAssertEqual(s.encounters, 16)
        XCTAssertEqual(state.lifetime.stepsCredited, 2000)
    }

    func testOfflineCap() {
        let long = Fixtures.longZoneFormulas
        var state = Fixtures.newGame(formulas: long)
        let s = OfflineSimulator(formulas: long).advance(&state, elapsed: 24 * 3600, newSteps: 0, now: Fixtures.t0)
        XCTAssertTrue(s.wasCapped)
        XCTAssertEqual(s.simulatedSeconds, 12 * 3600)
        XCTAssertEqual(s.tilesWalked, 720, accuracy: 1e-6)
        XCTAssertEqual(s.encounters, 120)
    }

    func testStepsAreNotCappedByTime() {
        let long = Fixtures.longZoneFormulas
        var state = Fixtures.newGame(formulas: long)
        let s = OfflineSimulator(formulas: long).advance(&state, elapsed: 48 * 3600, newSteps: 20_000, now: Fixtures.t0)
        XCTAssertEqual(s.tilesWalked, 720 + 1000, accuracy: 1e-6)
    }

    func testIdleStopsAtGateAndTrickleDoesNoGateDamage() {
        var state = Fixtures.newGame()
        let s = sim.advance(&state, elapsed: 300 * 60, newSteps: 0, now: Fixtures.t0)
        XCTAssertTrue(s.reachedGate)
        XCTAssertEqual(s.tilesWalked, 240, accuracy: 1e-6)
        XCTAssertEqual(s.gateDamage, 0)
        XCTAssertTrue(state.isAtGate)
        XCTAssertEqual(state.gate?.name, "Bramble Knight")
        XCTAssertEqual(state.gate?.damage, 0)
        XCTAssertEqual(state.frontierProgress(f), 1)

        // More idle time: nothing moves, no damage.
        let s2 = sim.advance(&state, elapsed: 600 * 60, newSteps: 0, now: Fixtures.t0)
        XCTAssertEqual(s2.tilesWalked, 0)
        XCTAssertEqual(s2.encounters, 0)
        XCTAssertEqual(state.gate?.damage, 0)
    }

    func testStepsAfterGateReachedDamageIt() {
        var state = Fixtures.newGame()
        Fixtures.atGate(&state)
        XCTAssertTrue(state.isAtGate)
        let s = sim.advance(&state, elapsed: 3600, newSteps: 3000, now: Fixtures.t0)
        XCTAssertEqual(s.gateDamage, 3000, accuracy: 1e-6)
        XCTAssertEqual(s.tilesWalked, 0)
        XCTAssertEqual(state.gate?.remaining, 5000)
    }

    func testOnlyStepsAfterReachingGateCount() {
        var state = Fixtures.newGame()
        // 50 steps/min -> 3.5 tiles/min. Gate (240 tiles) is reached in minute 69 (~68.57 min).
        // Steps before that walk the hero; the remaining ~2571 hit the gate.
        let s = sim.advance(&state, elapsed: 120 * 60, newSteps: 6000, now: Fixtures.t0)
        XCTAssertTrue(s.reachedGate)
        XCTAssertEqual(s.gateDamage, 2571, accuracy: 60)
        XCTAssertLessThan(s.gateDamage, 6000)
        XCTAssertTrue(state.isAtGate)
    }

    func testBreakingGateUnlocksNextZone() {
        var state = Fixtures.newGame()
        Fixtures.atGate(&state)
        state.hero.currentHP = 5
        let s = sim.advance(&state, elapsed: 60, newSteps: 8000, now: Fixtures.t0)
        XCTAssertEqual(s.gatesBroken, [1])
        XCTAssertEqual(s.zonesEntered, [2])
        XCTAssertEqual(state.trail.frontierZoneId, 2)
        XCTAssertEqual(state.trail.frontierTile, 0)
        XCTAssertNil(state.gate)
        XCTAssertFalse(state.isAtGate)
        XCTAssertTrue(s.loot.contains { $0.rarityId == "rare" && $0.zoneId == 1 })
        XCTAssertEqual(state.hero.currentHP, state.hero.maxHP(f), "full heal on breaking a gate")
        XCTAssertEqual(state.lifetime.gatesBroken, 1)
        XCTAssertEqual(state.clearedZoneIds(f), [1])
    }

    func testDefeatHealsToConfiguredPercent() {
        let deadly = Fixtures.deadlyFormulas
        var state = Fixtures.newGame(formulas: deadly)
        let s = OfflineSimulator(formulas: deadly).advance(&state, elapsed: 6 * 60, newSteps: 0, now: Fixtures.t0)
        XCTAssertEqual(s.encounters, 1)
        XCTAssertEqual(s.defeats, 1)
        XCTAssertEqual(s.kills, 0)
        XCTAssertEqual(s.xp, 0)
        XCTAssertEqual(state.hero.currentHP, Int(Double(state.hero.maxHP(deadly)) * deadly.combat.defeatHealPercent))
    }

    func testDeterministicGivenSeed() {
        var a = Fixtures.newGame(seed: 9)
        var b = Fixtures.newGame(seed: 9)
        let sa = sim.advance(&a, elapsed: 8 * 3600, newSteps: 9000, now: Fixtures.t0)
        let sb = sim.advance(&b, elapsed: 8 * 3600, newSteps: 9000, now: Fixtures.t0)
        XCTAssertEqual(sa, sb)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsDiverge() {
        var a = Fixtures.newGame(seed: 1)
        var b = Fixtures.newGame(seed: 2)
        sim.advance(&a, elapsed: 4 * 3600, newSteps: 0, now: Fixtures.t0)
        sim.advance(&b, elapsed: 4 * 3600, newSteps: 0, now: Fixtures.t0)
        XCTAssertNotEqual(a.rng, b.rng)
    }

    func testSummaryTotalsMatchState() {
        let long = Fixtures.longZoneFormulas
        var state = Fixtures.newGame(formulas: long)
        let s = OfflineSimulator(formulas: long).advance(&state, elapsed: 12 * 3600, newSteps: 30_000, now: Fixtures.t0)
        XCTAssertGreaterThan(s.kills, 0)
        XCTAssertGreaterThan(s.levelUps, 0)
        XCTAssertEqual(s.endLevel, s.startLevel + s.levelUps)
        XCTAssertEqual(state.hero.gold, s.gold)
        XCTAssertEqual(state.hero.totalXP, s.xp)
        XCTAssertEqual(state.lifetime.kills, s.kills)
        XCTAssertEqual(state.hero.inventory.count + state.hero.equipment.all.count, s.loot.count)
    }

    func testNegativeElapsedDoesNothing() {
        var state = Fixtures.newGame()
        let later = Fixtures.t0.addingTimeInterval(100)
        let s = sim.advance(&state, elapsed: -3600, newSteps: 0, now: later)
        XCTAssertEqual(s.tilesWalked, 0)
        XCTAssertEqual(state.lastSimulatedAt, later)
    }

    func testCatchUpUsesLastSimulatedAt() {
        var state = Fixtures.newGame()
        let s = sim.catchUp(&state, newSteps: 0, now: Fixtures.t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(s.tilesWalked, 30, accuracy: 1e-6)
    }

    func testGrindingEarlierZoneWhileGateStillTakesSteps() {
        var state = Fixtures.newGame()
        Fixtures.atGate(&state)
        sim.advance(&state, elapsed: 0, newSteps: 8000, now: Fixtures.t0) // break gate 1
        Fixtures.atGate(&state) // now at gate 2
        XCTAssertEqual(state.gate?.zoneId, 2)

        XCTAssertFalse(state.travel(to: 3, formulas: f), "locked zone")
        XCTAssertTrue(state.travel(to: 1, formulas: f))
        XCTAssertTrue(state.trail.isGrinding)
        XCTAssertFalse(state.isAtGate)
        XCTAssertTrue(state.hasActiveGate)

        let s = sim.advance(&state, elapsed: 60 * 60, newSteps: 1000, now: Fixtures.t0)
        XCTAssertEqual(s.gateDamage, 1000, accuracy: 1e-6, "steps still hit the frontier gate")
        XCTAssertEqual(s.tilesWalked, 60 + 50, accuracy: 1e-6, "and also power the grind trail")
        XCTAssertEqual(state.trail.frontierTile, 320, "frontier position untouched")
        XCTAssertEqual(state.trail.grindTile, 110, accuracy: 1e-6)

        // Grind trail loops instead of stopping.
        sim.advance(&state, elapsed: 200 * 60, newSteps: 0, now: Fixtures.t0)
        XCTAssertEqual(state.trail.grindTile, 70, accuracy: 1e-6) // (110 + 200) mod 240

        XCTAssertTrue(state.travel(to: nil, formulas: f))
        XCTAssertTrue(state.isAtGate)
    }

    func testClearingFinalZoneLoopsTrail() {
        var state = Fixtures.newGame()
        for _ in f.zones {
            Fixtures.atGate(&state)
            sim.advance(&state, elapsed: 0, newSteps: 50_000, now: Fixtures.t0)
        }
        XCTAssertTrue(state.trail.allZonesCleared)
        XCTAssertEqual(state.trail.frontierZoneId, 3)
        XCTAssertEqual(state.clearedZoneIds(f), [1, 2, 3])
        let s = sim.advance(&state, elapsed: 500 * 60, newSteps: 0, now: Fixtures.t0)
        XCTAssertEqual(s.tilesWalked, 500, accuracy: 1e-6)
        XCTAssertFalse(s.reachedGate)
        XCTAssertNil(state.gate)
    }

    func testGameStateCodableRoundTrip() throws {
        var state = Fixtures.newGame()
        sim.advance(&state, elapsed: 12 * 3600, newSteps: 12_000, now: Fixtures.t0)
        _ = state.ledger.ingest(dailyTotals: ["2026-10-02": 5000])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoded = try decoder.decode(GameState.self, from: data)
        XCTAssertEqual(decoded, state)
    }
}

final class FightLogTests: XCTestCase {
    func testRecentFightsAreCapped() {
        var state = Fixtures.newGame()
        let s = OfflineSimulator(formulas: Fixtures.formulas).advance(&state, elapsed: 3 * 3600, newSteps: 0, now: Fixtures.t0)
        XCTAssertEqual(s.encounters, 30)
        XCTAssertEqual(s.recentFights.count, OfflineSummary.maxFightLogs)
        XCTAssertEqual(s.recentFights.filter(\.heroWon).count + s.recentFights.filter { !$0.heroWon }.count, OfflineSummary.maxFightLogs)
    }
}
