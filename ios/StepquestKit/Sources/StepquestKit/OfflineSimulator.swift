import Foundation

/// One resolved idle fight (kept for the trail scene to replay with damage numbers).
public struct FightLog: Codable, Sendable, Equatable {
    public var monster: MonsterDefinition
    public var zoneId: Int
    public var heroWon: Bool
    public var heroHits: Int
    public var heroDamagePerHit: Int
    public var monsterHits: Int
    public var monsterDamagePerHit: Int
}

/// What happened while the app was closed (shown as the "While you were away" card).
public struct OfflineSummary: Codable, Sendable, Equatable {
    public var elapsedSeconds: Double = 0
    /// Elapsed time actually simulated (after `offlineCapHours`).
    public var simulatedSeconds: Double = 0
    public var stepsApplied: Int = 0
    public var tilesWalked: Double = 0
    public var bonusTiles: Double = 0
    public var encounters: Int = 0
    public var kills: Int = 0
    public var defeats: Int = 0
    public var xp: Int = 0
    public var gold: Int = 0
    public var levelUps: Int = 0
    public var startLevel: Int = 1
    public var endLevel: Int = 1
    public var loot: [Item] = []
    public var reachedGate: Bool = false
    public var gateDamage: Double = 0
    public var gatesBroken: [Int] = []
    public var zonesEntered: [Int] = []
    public var wasCapped: Bool = false
    /// The most recent fights (at most `maxFightLogs`).
    public var recentFights: [FightLog] = []
    public static let maxFightLogs = 8

    public init() {}

    public var isEmpty: Bool { tilesWalked < 0.5 && kills == 0 && defeats == 0 && gateDamage == 0 && gatesBroken.isEmpty }
}

/// Deterministic idle catch-up.
///
/// Given elapsed wall-clock time and the real steps credited since the last run:
/// - the hero walks at `baseTilesPerMinute` (base trickle) plus `steps * energyPerStep / energyPerBonusTile`
///   bonus tiles;
/// - every `encounterEveryTiles` tiles an encounter is resolved with `Combat.resolve` (1x multiplier);
/// - a defeat gives no rewards and revives the hero at `defeatHealPercent`;
/// - frontier movement stops at the Step Gate; steps credited after that point damage the gate (1x);
/// - elapsed time is capped at `offlineCapHours` (steps are real and never capped).
///
/// Steps are spread uniformly over the elapsed time in one-minute slices so the split between
/// "steps that walked to the gate" and "steps after the gate was reached" is deterministic.
public struct OfflineSimulator: Sendable {
    public let formulas: Formulas
    public static let sliceSeconds: Double = 60

    public init(formulas: Formulas) {
        self.formulas = formulas
    }

    /// Advances from `state.lastSimulatedAt` to `now`.
    @discardableResult
    public func catchUp(_ state: inout GameState, newSteps: Int, now: Date) -> OfflineSummary {
        let elapsed = now.timeIntervalSince(state.lastSimulatedAt)
        return advance(&state, elapsed: elapsed, newSteps: newSteps, now: now)
    }

    @discardableResult
    public func advance(_ state: inout GameState, elapsed: TimeInterval, newSteps: Int, now: Date) -> OfflineSummary {
        var summary = OfflineSummary()
        summary.startLevel = state.hero.level
        summary.endLevel = state.hero.level
        let elapsed = max(0, elapsed.isFinite ? elapsed : 0)
        let cap = formulas.idle.offlineCapHours * 3600
        let simulated = min(elapsed, cap)
        let steps = max(0, newSteps)
        summary.elapsedSeconds = elapsed
        summary.simulatedSeconds = simulated
        summary.wasCapped = elapsed > cap
        summary.stepsApplied = steps
        state.lifetime.stepsCredited += steps

        let slices = max(1, Int((simulated / Self.sliceSeconds).rounded(.up)))
        for i in 0..<slices {
            let sliceStart = Double(i) * Self.sliceSeconds
            let dt = max(0, min(Self.sliceSeconds, simulated - sliceStart))
            // Integer split that sums exactly to `steps`.
            let sliceSteps = steps * (i + 1) / slices - steps * i / slices
            step(&state, dt: dt, steps: sliceSteps, now: now, summary: &summary)
        }

        state.lastSimulatedAt = now
        summary.endLevel = state.hero.level
        return summary
    }

    private func step(_ state: inout GameState, dt: Double, steps: Int, now: Date, summary: inout OfflineSummary) {
        var movementSteps = steps

        if state.hasActiveGate {
            if state.isAtGate {
                // Standing at the gate: every step hits the guardian, the hero doesn't move.
                applyGate(&state, steps: steps, now: now, summary: &summary)
                return
            } else {
                // Grinding elsewhere: steps still damage the frontier gate, and also power movement.
                applyGate(&state, steps: steps, now: now, summary: &summary)
            }
        }

        let trickle = dt / 60 * formulas.idle.baseTilesPerMinute
        let bonus = Double(movementSteps) * formulas.idle.energyPerStep / formulas.idle.energyPerBonusTile
        let requested = trickle + bonus
        let walk = state.walk(tiles: requested, formulas: formulas, now: now)
        summary.tilesWalked += walk.walked
        if requested > 0 { summary.bonusTiles += bonus * (walk.walked / requested) }

        resolveEncounters(&state, count: walk.encounters, summary: &summary)

        if walk.reachedGate {
            summary.reachedGate = true
            // Steps from the part of this slice after the gate was reached count toward it.
            let usedFraction = requested > 0 ? walk.walked / requested : 1
            movementSteps = Int((Double(steps) * (1 - usedFraction)).rounded(.down))
            applyGate(&state, steps: movementSteps, now: now, summary: &summary)
        }
    }

    private func applyGate(_ state: inout GameState, steps: Int, now: Date, summary: inout OfflineSummary) {
        guard let hit = state.applyGateSteps(steps, stride: false, formulas: formulas, now: now) else { return }
        summary.gateDamage += hit.dealt
        if hit.broken {
            summary.gatesBroken.append(hit.brokenZoneId)
            if let reward = hit.reward { summary.loot.append(reward) }
            if let zone = hit.newZone { summary.zonesEntered.append(zone.id) }
        }
    }

    private func resolveEncounters(_ state: inout GameState, count: Int, summary: inout OfflineSummary) {
        guard count > 0 else { return }
        for _ in 0..<count {
            summary.encounters += 1
            let monster = state.spawnMonster(formulas: formulas)
            let result = Combat.resolve(
                heroStats: state.hero.stats(formulas), heroHP: state.hero.currentHP,
                monster: monster.definition, config: formulas.combat)
            summary.recentFights.append(FightLog(
                monster: monster.definition, zoneId: monster.zoneId, heroWon: result.heroWon,
                heroHits: result.heroHits, heroDamagePerHit: result.heroDamagePerHit,
                monsterHits: result.monsterHits, monsterDamagePerHit: result.monsterDamagePerHit))
            if summary.recentFights.count > OfflineSummary.maxFightLogs { summary.recentFights.removeFirst() }
            if result.heroWon {
                state.hero.currentHP = result.heroHPAfter
                let reward = state.grantKill(monster.definition, zoneId: monster.zoneId, formulas: formulas)
                summary.kills += 1
                summary.xp += reward.xp
                summary.gold += reward.gold
                summary.levelUps += reward.levelsGained
                if let item = reward.item { summary.loot.append(item) }
            } else {
                summary.defeats += 1
                state.applyDefeat(formulas: formulas)
            }
        }
    }
}
