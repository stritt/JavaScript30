import Foundation
import XCTest
@testable import StepquestKit

final class HeroTests: XCTestCase {
    let f = Fixtures.formulas

    func testNewHeroStats() {
        let hero = Hero(formulas: f)
        XCTAssertEqual(hero.level, 1)
        XCTAssertEqual(hero.stats(f), StatBlock(hp: 40, atk: 8, def: 2))
        XCTAssertEqual(hero.currentHP, 40)
        XCTAssertEqual(hero.gold, 0)
    }

    func testStatsGrowPerLevel() {
        var hero = Hero(formulas: f)
        hero.level = 5
        XCTAssertEqual(hero.stats(f), StatBlock(hp: 40 + 4 * 8, atk: 8 + 4 * 2, def: 2 + 4))
    }

    func testXPCurve() {
        // floor(50 * level^1.6)
        XCTAssertEqual(XPCurve.xpToNext(level: 1, config: f.hero), 50)
        XCTAssertEqual(XPCurve.xpToNext(level: 2, config: f.hero), Int((50 * pow(2.0, 1.6)).rounded(.down)))
        XCTAssertEqual(XPCurve.xpToNext(level: 2, config: f.hero), 151)
        XCTAssertEqual(XPCurve.xpToNext(level: 10, config: f.hero), 1990)
        XCTAssertEqual(XPCurve.totalXP(toReach: 1, config: f.hero), 0)
        XCTAssertEqual(XPCurve.totalXP(toReach: 3, config: f.hero), 50 + 151)
        for level in 1..<98 {
            XCTAssertLessThan(XPCurve.xpToNext(level: level, config: f.hero), XPCurve.xpToNext(level: level + 1, config: f.hero))
        }
    }

    func testGainXPLevelsUpAndHeals() {
        var hero = Hero(formulas: f)
        hero.currentHP = 3
        XCTAssertEqual(hero.gainXP(49, formulas: f), 0)
        XCTAssertEqual(hero.currentHP, 3)
        XCTAssertEqual(hero.gainXP(1, formulas: f), 1)
        XCTAssertEqual(hero.level, 2)
        XCTAssertEqual(hero.xp, 0)
        XCTAssertEqual(hero.currentHP, hero.maxHP(f))
        // Multi-level jump with carry-over.
        XCTAssertEqual(hero.gainXP(151 + 50, formulas: f), 1)
        XCTAssertEqual(hero.level, 3)
        XCTAssertEqual(hero.xp, 50)
        XCTAssertEqual(hero.totalXP, 50 + 151 + 50)
    }

    func testMaxLevelStopsLeveling() {
        var hero = Hero(formulas: f)
        hero.gainXP(Int.max / 4, formulas: f)
        XCTAssertEqual(hero.level, 99)
        XCTAssertEqual(hero.xp, 0)
        XCTAssertEqual(hero.gainXP(1000, formulas: f), 0)
        XCTAssertEqual(hero.level, 99)
    }

    func testEquipUnequipAndStats() {
        var hero = Hero(formulas: f)
        let sword = Item(id: "s", name: "Sword", slot: .weapon, rarityId: "common", zoneId: 1, power: 3, bonus: StatBlock(atk: 3))
        let sword2 = Item(id: "s2", name: "Better", slot: .weapon, rarityId: "rare", zoneId: 1, power: 5, bonus: StatBlock(atk: 5))
        let charm = Item(id: "c", name: "Charm", slot: .charm, rarityId: "common", zoneId: 1, power: 3, bonus: StatBlock(hp: 12))
        hero.inventory = [sword, sword2, charm]

        XCTAssertTrue(hero.equip(itemId: "s", formulas: f))
        XCTAssertEqual(hero.stats(f).atk, 11)
        XCTAssertTrue(hero.equip(itemId: "s2", formulas: f))
        XCTAssertEqual(hero.stats(f).atk, 13)
        XCTAssertEqual(Set(hero.inventory.map(\.id)), ["s", "c"])
        XCTAssertFalse(hero.equip(itemId: "nope", formulas: f))

        hero.equip(itemId: "c", formulas: f)
        XCTAssertEqual(hero.maxHP(f), 52)
        hero.currentHP = 52
        XCTAssertTrue(hero.unequip(.charm, formulas: f))
        XCTAssertEqual(hero.currentHP, 40, "HP clamps to new max")
        XCTAssertFalse(hero.unequip(.armor, formulas: f))
    }

    func testReceiveAutoEquip() {
        var hero = Hero(formulas: f)
        let weak = Item(id: "w", name: "Weak", slot: .weapon, rarityId: "common", zoneId: 1, power: 2, bonus: StatBlock(atk: 2))
        let strong = Item(id: "x", name: "Strong", slot: .weapon, rarityId: "rare", zoneId: 1, power: 9, bonus: StatBlock(atk: 9))
        let weaker = Item(id: "y", name: "Weaker", slot: .weapon, rarityId: "common", zoneId: 1, power: 1, bonus: StatBlock(atk: 1))

        XCTAssertTrue(hero.receive(weak, autoEquip: false, formulas: f), "empty slot is always filled")
        XCTAssertFalse(hero.receive(strong, autoEquip: false, formulas: f))
        XCTAssertEqual(hero.equipment.weapon?.id, "w")
        hero.equip(itemId: "x", formulas: f)
        XCTAssertFalse(hero.receive(weaker, autoEquip: true, formulas: f))
        XCTAssertEqual(hero.equipment.weapon?.id, "x")
        XCTAssertEqual(hero.inventory.count, 2)
    }

    func testDefeatHeal() {
        var hero = Hero(formulas: f)
        hero.currentHP = 0
        hero.heal(toFraction: f.combat.defeatHealPercent, formulas: f)
        XCTAssertEqual(hero.currentHP, 20)
    }
}
