import Foundation

/// HP / attack / defense triple used for hero base stats, per-level growth and gear bonuses.
public struct StatBlock: Codable, Sendable, Equatable, Hashable {
    public var hp: Int
    public var atk: Int
    public var def: Int

    public init(hp: Int = 0, atk: Int = 0, def: Int = 0) {
        self.hp = hp
        self.atk = atk
        self.def = def
    }

    public static let zero = StatBlock()

    public static func + (lhs: StatBlock, rhs: StatBlock) -> StatBlock {
        StatBlock(hp: lhs.hp + rhs.hp, atk: lhs.atk + rhs.atk, def: lhs.def + rhs.def)
    }

    public static func += (lhs: inout StatBlock, rhs: StatBlock) { lhs = lhs + rhs }

    public static func * (lhs: StatBlock, rhs: Int) -> StatBlock {
        StatBlock(hp: lhs.hp * rhs, atk: lhs.atk * rhs, def: lhs.def * rhs)
    }
}

/// A Stride Mode cadence tier (Stroll / March / Rush / Frenzy).
public struct CadenceTier: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var minSpm: Double
    public var damageMultiplier: Double
    public var combo: Bool
    public var critChance: Double

    public init(id: String, name: String, minSpm: Double, damageMultiplier: Double, combo: Bool, critChance: Double) {
        self.id = id
        self.name = name
        self.minSpm = minSpm
        self.damageMultiplier = damageMultiplier
        self.combo = combo
        self.critChance = critChance
    }
}

/// Visual palette key for a zone. Unknown palettes from a newer server config decode to `.unknown`.
public enum ZonePalette: String, Codable, Sendable, CaseIterable {
    case meadow, forest, desert, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ZonePalette(rawValue: raw) ?? .unknown
    }
}

public struct MonsterDefinition: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var hp: Int
    public var atk: Int
    public var def: Int
    public var xp: Int
    public var gold: Int

    public init(id: String, name: String, hp: Int, atk: Int, def: Int, xp: Int, gold: Int) {
        self.id = id
        self.name = name
        self.hp = hp
        self.atk = atk
        self.def = def
        self.xp = xp
        self.gold = gold
    }
}

public struct GateDefinition: Codable, Sendable, Equatable, Hashable {
    public var name: String
    /// Real-step damage required to break the gate.
    public var stepHp: Int
}

public struct ZoneDefinition: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var lengthTiles: Int
    public var palette: ZonePalette
    public var monsters: [MonsterDefinition]
    public var gate: GateDefinition
}

public enum EquipmentSlot: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case weapon, armor, charm
    public var id: String { rawValue }
}

public struct RarityDefinition: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var weight: Double
    public var statMultiplier: Double
}

/// Runtime monster with mutable HP (used by Stride Mode and the trail scene).
public struct Monster: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var definition: MonsterDefinition
    public var zoneId: Int
    public var currentHP: Int

    public init(definition: MonsterDefinition, zoneId: Int, instanceId: String) {
        self.id = instanceId
        self.definition = definition
        self.zoneId = zoneId
        self.currentHP = definition.hp
    }

    public var maxHP: Int { definition.hp }
    public var isDead: Bool { currentHP <= 0 }
    public var stats: StatBlock { StatBlock(hp: definition.hp, atk: definition.atk, def: definition.def) }
}
