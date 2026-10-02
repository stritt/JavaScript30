import Foundation
import XCTest
@testable import StepquestKit

final class CombatTests: XCTestCase {
    let f = Fixtures.formulas

    func testDamageFormula() {
        XCTAssertEqual(Combat.damage(atk: 6, def: 0), 6)
        XCTAssertEqual(Combat.damage(atk: 6, def: 2), 4)
        XCTAssertEqual(Combat.damage(atk: 6, def: 10), 1, "minimum 1")
        XCTAssertEqual(Combat.damage(atk: 6, multiplier: 4, def: 4), 20)
        XCTAssertEqual(Combat.damage(atk: 5, multiplier: 1.5, def: 0), 7, "floored")
    }

    func testLevelOneHeroBeatsSlime() {
        let slime = f.zones[0].monsters[0] // hp 18 atk 4 def 0
        let r = Combat.resolve(heroStats: StatBlock(hp: 40, atk: 6, def: 2), heroHP: 40, monster: slime, config: f.combat)
        XCTAssertTrue(r.heroWon)
        XCTAssertEqual(r.heroHits, 3)
        XCTAssertEqual(r.durationSeconds, 3, accuracy: 1e-9)
        // Slime hits at 1.25s and 2.5s for 2 each before the 3.0s killing blow.
        XCTAssertEqual(r.monsterHits, 2)
        XCTAssertEqual(r.heroDamageTaken, 4)
        XCTAssertEqual(r.heroHPAfter, 36)
    }

    func testTieGoesToHero() {
        // Hero needs 2 hits (t=2.0). Monster needs 2 hits at aps 1.0 (t=2.0) as well.
        var config = f.combat
        config.monsterAttacksPerSecond = 1
        let m = MonsterDefinition(id: "m", name: "M", hp: 10, atk: 10, def: 0, xp: 1, gold: 1)
        let r = Combat.resolve(heroStats: StatBlock(hp: 10, atk: 5, def: 5), heroHP: 10, monster: m, config: config)
        XCTAssertTrue(r.heroWon)
        XCTAssertEqual(r.monsterHits, 1)
        XCTAssertEqual(r.heroHPAfter, 5)
    }

    func testHeroLoses() {
        let goblin = f.zones[0].monsters[2]
        let r = Combat.resolve(heroStats: StatBlock(hp: 40, atk: 6, def: 2), heroHP: 1, monster: goblin, config: f.combat)
        XCTAssertFalse(r.heroWon)
        XCTAssertEqual(r.heroHPAfter, 0)
        XCTAssertEqual(r.monsterHits, 1)
        XCTAssertEqual(r.heroHits, 1, "hero swings once at 1.0s before dying at 1.25s")
    }

    func testMultiplierSpeedsUpKills() {
        let treant = f.zones[1].monsters[2]
        let stats = StatBlock(hp: 100, atk: 20, def: 10)
        let normal = Combat.resolve(heroStats: stats, heroHP: 100, monster: treant, config: f.combat)
        let frenzy = Combat.resolve(heroStats: stats, heroHP: 100, monster: treant, multiplier: 4, config: f.combat)
        XCTAssertLessThan(frenzy.durationSeconds, normal.durationSeconds)
    }
}

final class LootTests: XCTestCase {
    let f = Fixtures.formulas

    func testPowerScalesWithZoneAndRarity() {
        let common = f.rarity(id: "common")!
        let legendary = f.rarity(id: "legendary")!
        XCTAssertEqual(LootGenerator.power(zoneId: 1, rarity: common, config: f.loot), 3)
        XCTAssertEqual(LootGenerator.power(zoneId: 3, rarity: common, config: f.loot), 9)
        XCTAssertEqual(LootGenerator.power(zoneId: 2, rarity: legendary, config: f.loot), 19) // 3*2*3.2=19.2
    }

    func testSlotToStatMapping() {
        let gen = LootGenerator(formulas: f)
        XCTAssertEqual(gen.bonus(slot: .weapon, power: 5), StatBlock(atk: 5))
        XCTAssertEqual(gen.bonus(slot: .armor, power: 5), StatBlock(def: 5))
        XCTAssertEqual(gen.bonus(slot: .charm, power: 5), StatBlock(hp: 20)) // perLevel hp/atk = 4
    }

    func testDropRateAndRarityDistribution() {
        let gen = LootGenerator(formulas: f)
        var rng = SplitMix64(seed: 2024)
        var drops: [Item] = []
        let trials = 50_000
        for _ in 0..<trials { if let item = gen.rollDrop(zoneId: 1, rng: &rng) { drops.append(item) } }
        XCTAssertEqual(Double(drops.count) / Double(trials), f.loot.dropChance, accuracy: 0.01)
        let commons = drops.filter { $0.rarityId == "common" }.count
        XCTAssertEqual(Double(commons) / Double(drops.count), 0.6, accuracy: 0.03)
        XCTAssertTrue(drops.contains { $0.rarityId == "legendary" })
        XCTAssertEqual(Set(drops.map(\.slot)), Set(EquipmentSlot.allCases))
    }

    func testGateRewardIsGuaranteedRarity() {
        let gen = LootGenerator(formulas: f)
        var rng = SplitMix64(seed: 1)
        for _ in 0..<20 { XCTAssertEqual(gen.gateReward(zoneId: 2, rng: &rng).rarityId, "rare") }
    }

    func testLootIsDeterministic() {
        let gen = LootGenerator(formulas: f)
        var a = SplitMix64(seed: 77)
        var b = SplitMix64(seed: 77)
        for _ in 0..<500 {
            XCTAssertEqual(gen.rollDrop(zoneId: 3, rng: &a), gen.rollDrop(zoneId: 3, rng: &b))
        }
    }

    func testItemNamesMatchRarity() {
        let gen = LootGenerator(formulas: f)
        var rng = SplitMix64(seed: 3)
        let legend = gen.makeItem(zoneId: 1, rarity: f.rarity(id: "legendary")!, slot: .weapon, rng: &rng)
        XCTAssertTrue(legend.name.hasSuffix("of Legend"))
        XCTAssertEqual(legend.slot, .weapon)
    }
}

final class StepGateTests: XCTestCase {
    let f = Fixtures.formulas

    func testNormalAndStrideDamage() {
        var gate = StepGate(zone: f.zones[0], reachedAt: Fixtures.t0)
        XCTAssertEqual(gate.stepHP, 8000)
        XCTAssertEqual(gate.apply(steps: 1000, stride: false, config: f.stride, at: Fixtures.t0), 1000)
        XCTAssertEqual(gate.apply(steps: 1000, stride: true, config: f.stride, at: Fixtures.t0), 1500)
        XCTAssertEqual(gate.remaining, 5500)
        XCTAssertEqual(gate.progress, 2500.0 / 8000, accuracy: 1e-9)
        XCTAssertEqual(gate.strideStepsToBreak(f.stride), 3667)
        XCTAssertFalse(gate.isBroken)
    }

    func testDamageClampsAndBreaks() {
        var gate = StepGate(zone: f.zones[0], reachedAt: Fixtures.t0)
        let later = Fixtures.t0.addingTimeInterval(3600)
        XCTAssertEqual(gate.apply(steps: 10_000, stride: false, config: f.stride, at: later), 8000)
        XCTAssertTrue(gate.isBroken)
        XCTAssertEqual(gate.brokenAt, later)
        XCTAssertEqual(gate.apply(steps: 10, stride: false, config: f.stride, at: later), 0)
        XCTAssertEqual(gate.remaining, 0)
    }

    func testZeroAndNegativeStepsDoNothing() {
        var gate = StepGate(zone: f.zones[1], reachedAt: Fixtures.t0)
        XCTAssertEqual(gate.apply(steps: 0, stride: true, config: f.stride, at: Fixtures.t0), 0)
        XCTAssertEqual(gate.apply(steps: -50, stride: false, config: f.stride, at: Fixtures.t0), 0)
        XCTAssertEqual(gate.damage, 0)
    }
}
