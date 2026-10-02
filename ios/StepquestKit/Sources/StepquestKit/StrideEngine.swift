import Foundation

public enum StrideEvent: Sendable, Equatable {
    case tierChanged(CadenceTier)
    case encounter(Monster)
    case heroHit(damage: Int, crit: Bool, monsterHPAfter: Int)
    case monsterHit(damage: Int, heroHPAfter: Int)
    case kill(KillReward)
    case levelUp(newLevel: Int)
    case defeat
    case reachedGate(StepGate)
    case gateHit(GateHit)
    case comboLevelUp(level: Int)
    case comboBroken
}

/// Real-time Stride Mode loop (app open, walking).
///
/// - Live pedometer steps move the hero (energy -> bonus tiles) on top of the base trickle.
/// - Encounters are fought blow by blow at `heroAttacksPerSecond`; damage uses the current cadence tier's
///   `damageMultiplier`, plus the combo bonus in combo tiers and `critChance` x `critMultiplier` crits.
/// - Stride steps hit the frontier gate at `gateStepMultiplier` (1.5x).
/// - Applied steps are recorded in the `StepLedger` so the next HealthKit sync doesn't credit them twice.
public struct StrideEngine: Sendable {
    public let formulas: Formulas
    public private(set) var monster: Monster?
    public private(set) var combo = Combo()
    public private(set) var tier: CadenceTier
    public private(set) var sessionSteps = 0
    public private(set) var sessionKills = 0
    public private(set) var sessionXP = 0
    public private(set) var sessionGold = 0
    public private(set) var sessionGateDamage = 0.0
    public private(set) var sessionLoot: [Item] = []

    private var heroCooldown = 0.0
    private var monsterCooldown = 0.0
    private var bankedTiles = 0.0
    private var pendingEncounters = 0

    public init(formulas: Formulas) {
        self.formulas = formulas
        self.tier = formulas.tier(forSpm: 0)
    }

    /// Damage multiplier for a hit at the current tier and combo (before crits).
    public var currentMultiplier: Double {
        tier.damageMultiplier * (1 + (tier.combo ? combo.bonus(formulas.stride) : 0))
    }

    public mutating func update(_ state: inout GameState, dt: TimeInterval, newSteps: Int, spm: Double, now: Date) -> [StrideEvent] {
        var events: [StrideEvent] = []
        let dt = max(0, dt)
        let steps = max(0, newSteps)

        // 1. Cadence tier + combo.
        let newTier = formulas.tier(forSpm: spm)
        if newTier.id != tier.id {
            tier = newTier
            events.append(.tierChanged(newTier))
        }
        let comboDelta = combo.register(steps: steps, tier: tier, config: formulas.stride)
        if comboDelta > 0 { events.append(.comboLevelUp(level: combo.level(formulas.stride))) }
        if comboDelta < 0 { events.append(.comboBroken) }

        // 2. Ledger: these steps are now credited.
        if steps > 0 {
            state.ledger.recordStrideSteps(steps)
            state.lifetime.strideSteps += steps
            state.lifetime.stepsCredited += steps
            sessionSteps += steps
        }

        // 3. Gate damage (1.5x for stride steps).
        let wasAtGate = state.isAtGate
        if steps > 0, let hit = state.applyGateSteps(steps, stride: true, formulas: formulas, now: now) {
            sessionGateDamage += hit.dealt
            events.append(.gateHit(hit))
            if hit.broken, let reward = hit.reward { sessionLoot.append(reward) }
        }

        // 4. Movement (paused while fighting; step energy is banked meanwhile).
        let trickle = dt / 60 * formulas.idle.baseTilesPerMinute
        let bonus = wasAtGate ? 0 : Double(steps) * formulas.idle.energyPerStep / formulas.idle.energyPerBonusTile
        if monster == nil {
            let walk = state.walk(tiles: trickle + bonus + bankedTiles, formulas: formulas, now: now)
            bankedTiles = 0
            pendingEncounters += walk.encounters
            if walk.reachedGate, let gate = state.gate { events.append(.reachedGate(gate)) }
            if pendingEncounters > 0 {
                pendingEncounters -= 1
                spawn(&state, events: &events)
            }
        } else {
            bankedTiles += bonus
        }

        // 5. Combat, interleaving both attackers in time order.
        if monster != nil {
            heroCooldown -= dt
            monsterCooldown -= dt
            while let current = monster, (heroCooldown <= 0 || monsterCooldown <= 0) {
                if heroCooldown <= monsterCooldown {
                    heroCooldown += 1 / formulas.combat.heroAttacksPerSecond
                    heroAttack(&state, current: current, events: &events)
                } else {
                    monsterCooldown += 1 / formulas.combat.monsterAttacksPerSecond
                    monsterAttack(&state, current: current, events: &events)
                }
            }
        }

        state.lastSimulatedAt = now
        return events
    }

    private mutating func spawn(_ state: inout GameState, events: inout [StrideEvent]) {
        let m = state.spawnMonster(formulas: formulas)
        monster = m
        heroCooldown = 1 / formulas.combat.heroAttacksPerSecond
        monsterCooldown = 1 / formulas.combat.monsterAttacksPerSecond
        events.append(.encounter(m))
    }

    private mutating func heroAttack(_ state: inout GameState, current: Monster, events: inout [StrideEvent]) {
        var m = current
        let crit = state.rng.chance(tier.critChance)
        var dmg = Combat.damage(atk: state.hero.stats(formulas).atk, multiplier: currentMultiplier, def: m.definition.def)
        if crit { dmg = Int((Double(dmg) * formulas.stride.critMultiplier).rounded(.down)) }
        m.currentHP = max(0, m.currentHP - dmg)
        events.append(.heroHit(damage: dmg, crit: crit, monsterHPAfter: m.currentHP))
        if m.isDead {
            monster = nil
            let reward = state.grantKill(m.definition, zoneId: m.zoneId, formulas: formulas)
            sessionKills += 1
            sessionXP += reward.xp
            sessionGold += reward.gold
            if let item = reward.item { sessionLoot.append(item) }
            events.append(.kill(reward))
            if reward.levelsGained > 0 { events.append(.levelUp(newLevel: state.hero.level)) }
        } else {
            monster = m
        }
    }

    private mutating func monsterAttack(_ state: inout GameState, current: Monster, events: inout [StrideEvent]) {
        let dmg = Combat.damage(atk: current.definition.atk, def: state.hero.stats(formulas).def)
        state.hero.currentHP = max(0, state.hero.currentHP - dmg)
        events.append(.monsterHit(damage: dmg, heroHPAfter: state.hero.currentHP))
        if state.hero.currentHP <= 0 {
            monster = nil
            state.applyDefeat(formulas: formulas)
            events.append(.defeat)
        }
    }
}
