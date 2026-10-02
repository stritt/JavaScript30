import Foundation
import XCTest
@testable import StepquestKit

final class StrideEngineTests: XCTestCase {
    let f = Fixtures.formulas

    func testTierChangeAndMultiplier() {
        var state = Fixtures.newGame()
        var engine = StrideEngine(formulas: f)
        XCTAssertEqual(engine.tier.id, "stroll")
        let events = engine.update(&state, dt: 0.1, newSteps: 0, spm: 140, now: Fixtures.t0)
        XCTAssertTrue(events.contains(.tierChanged(f.tier(forSpm: 140))))
        XCTAssertEqual(engine.tier.id, "frenzy")
        XCTAssertEqual(engine.currentMultiplier, 4)
    }

    func testStrideStepsHitGateAtMultiplierAndAreCreditedInLedger() {
        var state = Fixtures.newGame()
        Fixtures.atGate(&state)
        var engine = StrideEngine(formulas: f)
        let events = engine.update(&state, dt: 1, newSteps: 1000, spm: 110, now: Fixtures.t0)
        XCTAssertEqual(state.gate?.damage, 1500)
        XCTAssertEqual(engine.sessionGateDamage, 1500)
        XCTAssertEqual(state.ledger.strideCredit, 1000)
        XCTAssertTrue(events.contains { if case .gateHit = $0 { return true } else { return false } })
        XCTAssertEqual(state.trail.frontierTile, 240, "no movement at the gate")

        // The same steps arriving later via HealthKit are not credited twice.
        XCTAssertEqual(state.ledger.ingest(dailyTotals: ["2026-10-02": 1000]), 0)
    }

    func testWalkingFightsAndKills() {
        var state = Fixtures.newGame(seed: 11)
        var engine = StrideEngine(formulas: f)
        var encounters = 0
        var hits = 0
        var now = Fixtures.t0
        // 10 minutes at ~120 spm, ticking every 0.5s.
        for _ in 0..<1200 {
            now += 0.5
            for e in engine.update(&state, dt: 0.5, newSteps: 1, spm: 120, now: now) {
                switch e {
                case .encounter: encounters += 1
                case .heroHit: hits += 1
                default: break
                }
            }
        }
        XCTAssertGreaterThan(encounters, 0)
        XCTAssertGreaterThan(hits, 0)
        XCTAssertGreaterThan(engine.sessionKills, 0)
        XCTAssertEqual(engine.sessionSteps, 1200)
        XCTAssertEqual(state.lifetime.strideSteps, 1200)
        XCTAssertEqual(state.lastSimulatedAt, now)
        XCTAssertEqual(state.hero.gold, engine.sessionGold)
    }

    func testComboEventsInRush() {
        var state = Fixtures.newGame()
        var engine = StrideEngine(formulas: f)
        let events = engine.update(&state, dt: 1, newSteps: 60, spm: 115, now: Fixtures.t0)
        XCTAssertTrue(events.contains(.comboLevelUp(level: 1)))
        XCTAssertEqual(engine.currentMultiplier, 3 * 1.1, accuracy: 1e-9)
        let slow = engine.update(&state, dt: 1, newSteps: 1, spm: 50, now: Fixtures.t0)
        XCTAssertTrue(slow.contains(.comboBroken))
        XCTAssertEqual(engine.currentMultiplier, 1)
    }

    func testHigherTierKillsFaster() {
        func secondsToFirstKill(spm: Double) -> Double {
            var state = Fixtures.newGame(seed: 5)
            var engine = StrideEngine(formulas: f)
            // Walk straight into an encounter.
            _ = engine.update(&state, dt: 0, newSteps: 120, spm: spm, now: Fixtures.t0)
            XCTAssertNotNil(engine.monster)
            var t = 0.0
            while engine.sessionKills == 0 && t < 120 {
                t += 0.1
                _ = engine.update(&state, dt: 0.1, newSteps: 0, spm: spm, now: Fixtures.t0)
            }
            return t
        }
        XCTAssertLessThan(secondsToFirstKill(spm: 140), secondsToFirstKill(spm: 20))
    }
}
