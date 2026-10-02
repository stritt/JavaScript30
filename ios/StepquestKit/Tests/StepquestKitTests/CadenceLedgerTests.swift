import Foundation
import XCTest
@testable import StepquestKit

final class CadenceTierTests: XCTestCase {
    let f = Fixtures.formulas

    func testTierBoundaries() {
        XCTAssertEqual(f.tier(forSpm: 0).id, "stroll")
        XCTAssertEqual(f.tier(forSpm: 59.9).id, "stroll")
        XCTAssertEqual(f.tier(forSpm: 60).id, "march")
        XCTAssertEqual(f.tier(forSpm: 99.99).id, "march")
        XCTAssertEqual(f.tier(forSpm: 100).id, "rush")
        XCTAssertEqual(f.tier(forSpm: 129).id, "rush")
        XCTAssertEqual(f.tier(forSpm: 130).id, "frenzy")
        XCTAssertEqual(f.tier(forSpm: 400).id, "frenzy")
        XCTAssertEqual(f.tier(forSpm: -5).id, "stroll")
    }

    func testTierMultipliers() {
        XCTAssertEqual(f.stride.tiers.map(\.damageMultiplier), [1, 2, 3, 4])
        XCTAssertEqual(f.tier(forSpm: 140).critChance, 0.2)
        XCTAssertTrue(f.tier(forSpm: 110).combo)
        XCTAssertFalse(f.tier(forSpm: 80).combo)
    }
}

final class CadenceTrackerTests: XCTestCase {
    func testSteadyCadence() {
        var t = CadenceTracker(window: 10)
        // 2 steps per second = 120 spm, reported every second.
        for s in 0...20 { t.record(cumulativeSteps: s * 2, at: Double(s)) }
        XCTAssertEqual(t.spm(at: 20), 120, accuracy: 0.001)
        XCTAssertLessThanOrEqual(t.samples.count, 12, "old samples are pruned")
    }

    func testSparseUpdatesStillAccurate() {
        var t = CadenceTracker(window: 10)
        // CMPedometer often reports every ~2.5s.
        var time = 0.0
        var steps = 0
        while time <= 30 {
            t.record(cumulativeSteps: steps, at: time)
            time += 2.5
            steps += 4 // 4 steps per 2.5 s = 96 spm
        }
        XCTAssertEqual(t.spm(at: time - 2.5), 96, accuracy: 0.5)
    }

    func testDecaysWhenWalkerStops() {
        var t = CadenceTracker(window: 10)
        for s in 0...10 { t.record(cumulativeSteps: s * 2, at: Double(s)) }
        XCTAssertGreaterThan(t.spm(at: 10), 100)
        XCTAssertLessThan(t.spm(at: 15), t.spm(at: 10))
        XCTAssertEqual(t.spm(at: 25), 0)
    }

    func testEmptyAndRestart() {
        var t = CadenceTracker(window: 10)
        XCTAssertEqual(t.spm(at: 5), 0)
        t.record(cumulativeSteps: 100, at: 0)
        XCTAssertEqual(t.spm(at: 0.5), 0, "less than 1s of data")
        t.record(cumulativeSteps: 5, at: 1) // counter restarted
        XCTAssertEqual(t.samples.count, 1)
        t.record(cumulativeSteps: 7, at: 0.5) // out-of-order ignored
        XCTAssertEqual(t.samples.count, 1)
    }
}

final class ComboTests: XCTestCase {
    let f = Fixtures.formulas

    func testComboBuildsInRushAndCaps() {
        var combo = Combo()
        let rush = f.tier(forSpm: 110)
        XCTAssertEqual(combo.register(steps: 49, tier: rush, config: f.stride), 0)
        XCTAssertEqual(combo.level(f.stride), 0)
        XCTAssertEqual(combo.register(steps: 1, tier: rush, config: f.stride), 1)
        XCTAssertEqual(combo.bonus(f.stride), 0.1, accuracy: 1e-9)
        combo.register(steps: 1000, tier: rush, config: f.stride)
        XCTAssertEqual(combo.bonus(f.stride), f.stride.comboMaxBonus, "capped")
        XCTAssertTrue(combo.isMaxed(f.stride))
        XCTAssertEqual(combo.bestLevel, 21)
    }

    func testComboBreaksBelowRush() {
        var combo = Combo()
        combo.register(steps: 120, tier: f.tier(forSpm: 135), config: f.stride)
        XCTAssertEqual(combo.level(f.stride), 2)
        XCTAssertEqual(combo.register(steps: 5, tier: f.tier(forSpm: 70), config: f.stride), -1)
        XCTAssertEqual(combo.steps, 0)
        XCTAssertEqual(combo.register(steps: 5, tier: f.tier(forSpm: 70), config: f.stride), 0)
        XCTAssertEqual(combo.bestLevel, 2)
    }

    func testProgressToNextLevel() {
        var combo = Combo()
        combo.register(steps: 75, tier: f.tier(forSpm: 120), config: f.stride)
        XCTAssertEqual(combo.progressToNextLevel(f.stride), 0.5, accuracy: 1e-9)
    }
}

final class StepLedgerTests: XCTestCase {
    func testDeltasAcrossSyncs() {
        var ledger = StepLedger(startDay: "2026-10-01")
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-01": 1000]), 1000)
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-01": 1500]), 500)
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-01": 1500, "2026-10-02": 200]), 200)
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-01": 1500, "2026-10-02": 200]), 0)
    }

    func testIgnoresDaysBeforeStartAndDecreases() {
        var ledger = StepLedger(startDay: "2026-10-02")
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-09-30": 20_000, "2026-10-02": 300]), 300)
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-02": 250]), 0, "HealthKit correction downward")
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-02": 400]), 100)
    }

    func testStrideCreditPreventsDoubleCounting() {
        var ledger = StepLedger(startDay: "2026-10-02")
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-02": 1000]), 1000)
        ledger.recordStrideSteps(600) // walked live in Stride Mode
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-02": 1400]), 0)
        XCTAssertEqual(ledger.strideCredit, 200)
        XCTAssertEqual(ledger.ingest(dailyTotals: ["2026-10-02": 2000]), 400)
        XCTAssertEqual(ledger.strideCredit, 0)
    }

    func testPrunesOldDays() {
        var ledger = StepLedger(startDay: "2026-01-01")
        var totals: [String: Int] = [:]
        for d in 1...30 { totals[String(format: "2026-09-%02d", d)] = 100 }
        XCTAssertEqual(ledger.ingest(dailyTotals: totals), 3000)
        XCTAssertEqual(ledger.lastSeenByDay.count, 21)
        XCTAssertNotNil(ledger.lastSeenByDay["2026-09-30"])
    }

    func testDayKey() {
        XCTAssertEqual(DayKey.string(for: Fixtures.t0, calendar: Fixtures.utc), "2026-10-02")
    }
}
