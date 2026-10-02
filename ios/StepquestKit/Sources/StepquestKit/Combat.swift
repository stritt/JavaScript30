import Foundation

public enum Combat {
    /// `max(1, atk * multiplier - def)` from formulas.json, floored to an integer.
    public static func damage(atk: Int, multiplier: Double = 1, def: Int) -> Int {
        let raw = Double(atk) * multiplier - Double(def)
        return max(1, Int(raw.rounded(.down)))
    }

    public struct FightResult: Sendable, Equatable {
        public var heroWon: Bool
        public var heroHPAfter: Int
        public var heroDamageTaken: Int
        public var heroHits: Int
        public var monsterHits: Int
        public var durationSeconds: Double
        public var heroDamagePerHit: Int
        public var monsterDamagePerHit: Int
    }

    /// Deterministic auto-battle used by the idle/offline loop.
    ///
    /// Both sides attack on a fixed cadence (`heroAttacksPerSecond`, `monsterAttacksPerSecond`), first hits
    /// landing at `1/aps`. Whoever would land the killing blow first wins; ties go to the hero.
    /// Closed-form, so resolving thousands of offline fights is cheap.
    public static func resolve(
        heroStats: StatBlock,
        heroHP: Int,
        monster: MonsterDefinition,
        multiplier: Double = 1,
        config: Formulas.CombatConfig
    ) -> FightResult {
        let heroDmg = damage(atk: heroStats.atk, multiplier: multiplier, def: monster.def)
        let monsterDmg = damage(atk: monster.atk, def: heroStats.def)
        let hp = max(1, heroHP)

        let heroHitsNeeded = ceilDiv(max(1, monster.hp), heroDmg)
        let monsterHitsNeeded = ceilDiv(hp, monsterDmg)
        let heroTime = Double(heroHitsNeeded) / config.heroAttacksPerSecond
        let monsterTime = Double(monsterHitsNeeded) / config.monsterAttacksPerSecond

        if heroTime <= monsterTime + 1e-9 {
            // Monster hits that land strictly before the hero's killing blow.
            let x = heroTime * config.monsterAttacksPerSecond
            let landed = max(0, min(monsterHitsNeeded - 1, Int((x - 1e-9).rounded(.up)) - 1))
            let taken = landed * monsterDmg
            return FightResult(
                heroWon: true, heroHPAfter: hp - taken, heroDamageTaken: taken,
                heroHits: heroHitsNeeded, monsterHits: landed, durationSeconds: heroTime,
                heroDamagePerHit: heroDmg, monsterDamagePerHit: monsterDmg)
        } else {
            let x = monsterTime * config.heroAttacksPerSecond
            let landed = max(0, min(heroHitsNeeded - 1, Int((x + 1e-9).rounded(.down))))
            return FightResult(
                heroWon: false, heroHPAfter: 0, heroDamageTaken: hp,
                heroHits: landed, monsterHits: monsterHitsNeeded, durationSeconds: monsterTime,
                heroDamagePerHit: heroDmg, monsterDamagePerHit: monsterDmg)
        }
    }

    static func ceilDiv(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }
}
