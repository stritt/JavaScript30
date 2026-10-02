import Foundation

/// Where the hero is on the trail.
///
/// The *frontier* is the furthest zone unlocked; it ends in a Step Gate. While stuck at a gate the player
/// may send the hero to *grind* an earlier, cleared zone (that trail loops and has no gate). Steps taken after
/// the gate was reached keep damaging it either way.
public struct TrailState: Codable, Sendable, Equatable {
    public var frontierZoneId: Int
    public var frontierTile: Double
    public var grindZoneId: Int?
    public var grindTile: Double
    /// Tiles walked since the last encounter.
    public var encounterProgress: Double
    /// True once the last zone's gate is broken; the final zone then loops without a gate.
    public var allZonesCleared: Bool

    public init(frontierZoneId: Int) {
        self.frontierZoneId = frontierZoneId
        self.frontierTile = 0
        self.grindZoneId = nil
        self.grindTile = 0
        self.encounterProgress = 0
        self.allZonesCleared = false
    }

    public var activeZoneId: Int { grindZoneId ?? frontierZoneId }
    public var isGrinding: Bool { grindZoneId != nil }
}

public struct LifetimeStats: Codable, Sendable, Equatable {
    public var kills: Int = 0
    public var defeats: Int = 0
    public var tilesWalked: Double = 0
    public var stepsCredited: Int = 0
    public var strideSteps: Int = 0
    public var gatesBroken: Int = 0
    public var goldEarned: Int = 0

    public init() {}
}

/// The whole persisted save. Codable so it can be stored as JSON.
public struct GameState: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var createdAt: Date
    public var hero: Hero
    public var trail: TrailState
    /// The frontier gate, present from the moment it is reached until it breaks.
    public var gate: StepGate?
    public var rng: SplitMix64
    public var ledger: StepLedger
    /// Wall-clock time up to which idle progress has been simulated.
    public var lastSimulatedAt: Date
    public var lifetime: LifetimeStats
    /// Equip drops automatically when they beat the current item in that slot.
    public var autoEquip: Bool

    public init(formulas: Formulas, seed: UInt64, now: Date, heroName: String = "Wanderer", calendar: Calendar = .current) {
        self.schemaVersion = Self.currentSchemaVersion
        self.createdAt = now
        self.hero = Hero(name: heroName, formulas: formulas)
        self.trail = TrailState(frontierZoneId: formulas.firstZone.id)
        self.gate = nil
        self.rng = SplitMix64(seed: seed)
        self.ledger = StepLedger(startDay: DayKey.string(for: now, calendar: calendar))
        self.lastSimulatedAt = now
        self.lifetime = LifetimeStats()
        self.autoEquip = true
    }

    // MARK: Queries

    public func frontierZone(_ formulas: Formulas) -> ZoneDefinition {
        formulas.zone(id: trail.frontierZoneId) ?? formulas.firstZone
    }

    public func activeZone(_ formulas: Formulas) -> ZoneDefinition {
        formulas.zone(id: trail.activeZoneId) ?? frontierZone(formulas)
    }

    /// Hero is standing at an unbroken frontier gate (idle movement stopped).
    public var isAtGate: Bool { !trail.isGrinding && hasActiveGate }

    /// A frontier gate has been reached and is not yet broken (steps damage it).
    public var hasActiveGate: Bool { gate.map { !$0.isBroken } ?? false }

    /// 0...1 progress along the frontier zone toward its gate.
    public func frontierProgress(_ formulas: Formulas) -> Double {
        let length = Double(frontierZone(formulas).lengthTiles)
        return length > 0 ? min(1, trail.frontierTile / length) : 0
    }

    /// Tiles left before reaching the frontier gate.
    public func tilesToGate(_ formulas: Formulas) -> Double {
        max(0, Double(frontierZone(formulas).lengthTiles) - trail.frontierTile)
    }

    /// Zones whose gate has been broken (available for grinding).
    public func clearedZoneIds(_ formulas: Formulas) -> [Int] {
        formulas.zones.map(\.id).filter { $0 < trail.frontierZoneId || (trail.allZonesCleared && $0 == trail.frontierZoneId) }
    }

    public func isUnlocked(zoneId: Int) -> Bool { zoneId <= trail.frontierZoneId }

    // MARK: Player actions

    /// Sends the hero to grind a cleared zone, or back to the frontier when `zoneId` is the frontier (or nil).
    @discardableResult
    public mutating func travel(to zoneId: Int?, formulas: Formulas) -> Bool {
        guard let zoneId, zoneId != trail.frontierZoneId else {
            trail.grindZoneId = nil
            return true
        }
        guard clearedZoneIds(formulas).contains(zoneId) else { return false }
        if trail.grindZoneId != zoneId {
            trail.grindZoneId = zoneId
            trail.grindTile = 0
        }
        return true
    }

    @discardableResult
    public mutating func equip(itemId: String, formulas: Formulas) -> Bool { hero.equip(itemId: itemId, formulas: formulas) }

    @discardableResult
    public mutating func unequip(_ slot: EquipmentSlot, formulas: Formulas) -> Bool { hero.unequip(slot, formulas: formulas) }
}

// MARK: - Shared mechanics (used by OfflineSimulator and StrideEngine)

public struct WalkResult: Sendable, Equatable {
    public var walked: Double
    public var encounters: Int
    public var reachedGate: Bool
}

public struct KillReward: Sendable, Equatable {
    public var monster: MonsterDefinition
    public var xp: Int
    public var gold: Int
    public var levelsGained: Int
    public var item: Item?
    public var itemEquipped: Bool
}

public struct GateHit: Sendable, Equatable {
    public var dealt: Double
    public var broken: Bool
    public var reward: Item?
    /// The zone the frontier advanced to (nil if the broken gate was the last one).
    public var newZone: ZoneDefinition?
    public var brokenZoneId: Int
}

extension GameState {
    /// Moves the hero along the active trail. Frontier movement stops at the gate (creating it);
    /// grind trails and a fully cleared final zone loop forever.
    public mutating func walk(tiles: Double, formulas: Formulas, now: Date) -> WalkResult {
        guard tiles > 0 else { return WalkResult(walked: 0, encounters: 0, reachedGate: false) }
        var walked = 0.0
        var reachedGate = false

        if trail.isGrinding {
            let length = Double(activeZone(formulas).lengthTiles)
            trail.grindTile = (trail.grindTile + tiles).truncatingRemainder(dividingBy: max(1, length))
            walked = tiles
        } else if hasActiveGate {
            walked = 0
        } else {
            let zone = frontierZone(formulas)
            let length = Double(zone.lengthTiles)
            if trail.allZonesCleared {
                trail.frontierTile = (trail.frontierTile + tiles).truncatingRemainder(dividingBy: max(1, length))
                walked = tiles
            } else {
                let room = max(0, length - trail.frontierTile)
                if tiles >= room - 1e-9 {
                    walked = room
                    trail.frontierTile = length
                    gate = StepGate(zone: zone, reachedAt: now)
                    reachedGate = true
                } else {
                    trail.frontierTile += tiles
                    walked = tiles
                }
            }
        }

        trail.encounterProgress += walked
        lifetime.tilesWalked += walked
        let every = Double(max(1, formulas.combat.encounterEveryTiles))
        let encounters = Int((trail.encounterProgress + 1e-9) / every)
        trail.encounterProgress = max(0, trail.encounterProgress - Double(encounters) * every)
        return WalkResult(walked: walked, encounters: encounters, reachedGate: reachedGate)
    }

    /// Picks a monster for an encounter in the active zone.
    public mutating func spawnMonster(formulas: Formulas) -> Monster {
        let zone = activeZone(formulas)
        let definition = rng.pick(zone.monsters)
        return Monster(definition: definition, zoneId: zone.id, instanceId: rng.nextIdentifier())
    }

    /// XP, gold, loot roll and level-ups for a kill.
    public mutating func grantKill(_ monster: MonsterDefinition, zoneId: Int, formulas: Formulas) -> KillReward {
        hero.gold += monster.gold
        lifetime.goldEarned += monster.gold
        lifetime.kills += 1
        let levels = hero.gainXP(monster.xp, formulas: formulas)
        var equipped = false
        let item = LootGenerator(formulas: formulas).rollDrop(zoneId: zoneId, rng: &rng)
        if let item {
            equipped = hero.receive(item, autoEquip: autoEquip, formulas: formulas)
        }
        return KillReward(monster: monster, xp: monster.xp, gold: monster.gold, levelsGained: levels, item: item, itemEquipped: equipped)
    }

    /// Hero was defeated: no rewards, revive at `defeatHealPercent` of max HP.
    public mutating func applyDefeat(formulas: Formulas) {
        lifetime.defeats += 1
        hero.heal(toFraction: formulas.combat.defeatHealPercent, formulas: formulas)
    }

    /// Applies real steps to the frontier gate (if one is active). Breaking it unlocks the next zone,
    /// grants the guaranteed drop and fully heals the hero.
    public mutating func applyGateSteps(_ steps: Int, stride: Bool, formulas: Formulas, now: Date) -> GateHit? {
        guard var current = gate, !current.isBroken, steps > 0 else { return nil }
        let dealt = current.apply(steps: steps, stride: stride, config: formulas.stride, at: now)
        gate = current
        guard current.isBroken else {
            return GateHit(dealt: dealt, broken: false, reward: nil, newZone: nil, brokenZoneId: current.zoneId)
        }
        return breakGate(dealt: dealt, formulas: formulas)
    }

    private mutating func breakGate(dealt: Double, formulas: Formulas) -> GateHit {
        let zoneId = trail.frontierZoneId
        lifetime.gatesBroken += 1
        let reward = LootGenerator(formulas: formulas).gateReward(zoneId: zoneId, rng: &rng)
        hero.receive(reward, autoEquip: autoEquip, formulas: formulas)
        let next = formulas.nextZone(after: zoneId)
        if let next {
            trail.frontierZoneId = next.id
        } else {
            trail.allZonesCleared = true
        }
        trail.frontierTile = 0
        gate = nil
        hero.healFull(formulas)
        return GateHit(dealt: dealt, broken: true, reward: reward, newZone: next, brokenZoneId: zoneId)
    }
}
