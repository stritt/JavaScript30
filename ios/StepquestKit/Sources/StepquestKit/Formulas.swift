import Foundation

/// Codable mirror of `shared/formulas.json`. Every balance number in the game comes from here.
/// The app ships a bundled copy (`Formulas.bundled`) and refreshes it from `GET /v1/config`.
public struct Formulas: Codable, Sendable, Equatable {
    public var version: Int
    public var idle: Idle
    public var hero: HeroConfig
    public var combat: CombatConfig
    public var stride: StrideConfig
    public var zones: [ZoneDefinition]
    public var loot: LootConfig
    public var integrity: Integrity
    public var leaderboards: LeaderboardConfig

    public init(
        version: Int, idle: Idle, hero: HeroConfig, combat: CombatConfig, stride: StrideConfig,
        zones: [ZoneDefinition], loot: LootConfig, integrity: Integrity, leaderboards: LeaderboardConfig
    ) {
        self.version = version
        self.idle = idle
        self.hero = hero
        self.combat = combat
        self.stride = stride
        self.zones = zones
        self.loot = loot
        self.integrity = integrity
        self.leaderboards = leaderboards
    }

    // MARK: Sections

    public struct Idle: Codable, Sendable, Equatable {
        public var baseTilesPerMinute: Double
        public var energyPerStep: Double
        public var energyPerBonusTile: Double
        public var offlineCapHours: Double
    }

    public struct HeroConfig: Codable, Sendable, Equatable {
        public var base: StatBlock
        public var perLevel: StatBlock
        public var xpCurve: XPCurveConfig
        public var maxLevel: Int
    }

    public struct XPCurveConfig: Codable, Sendable, Equatable {
        public var base: Double
        public var exponent: Double
    }

    public struct CombatConfig: Codable, Sendable, Equatable {
        public var encounterEveryTiles: Int
        /// Informational only; the formula is implemented in `Combat.damage`.
        public var damageFormula: String?
        public var heroAttacksPerSecond: Double
        public var monsterAttacksPerSecond: Double
        public var defeatHealPercent: Double
    }

    public struct StrideConfig: Codable, Sendable, Equatable {
        public var gateStepMultiplier: Double
        public var cadenceWindowSeconds: Double
        public var tiers: [CadenceTier]
        public var comboStepsPerLevel: Int
        public var comboMaxBonus: Double
        public var critMultiplier: Double
        /// Bonus added per combo level. Not present in formulas.json v1, so it defaults to 0.1
        /// (5 combo levels = the 0.5 cap). The server may add the key later.
        public var comboBonusPerLevel: Double

        enum CodingKeys: String, CodingKey {
            case gateStepMultiplier, cadenceWindowSeconds, tiers, comboStepsPerLevel
            case comboMaxBonus, critMultiplier, comboBonusPerLevel
        }

        public static let defaultComboBonusPerLevel = 0.1

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            gateStepMultiplier = try c.decode(Double.self, forKey: .gateStepMultiplier)
            cadenceWindowSeconds = try c.decode(Double.self, forKey: .cadenceWindowSeconds)
            tiers = try c.decode([CadenceTier].self, forKey: .tiers).sorted { $0.minSpm < $1.minSpm }
            comboStepsPerLevel = try c.decode(Int.self, forKey: .comboStepsPerLevel)
            comboMaxBonus = try c.decode(Double.self, forKey: .comboMaxBonus)
            critMultiplier = try c.decode(Double.self, forKey: .critMultiplier)
            comboBonusPerLevel = try c.decodeIfPresent(Double.self, forKey: .comboBonusPerLevel)
                ?? Self.defaultComboBonusPerLevel
        }
    }

    public struct LootConfig: Codable, Sendable, Equatable {
        public var dropChance: Double
        public var slots: [EquipmentSlot]
        public var rarities: [RarityDefinition]
        public var baseStatPerZone: Double
        public var gateGuaranteedRarity: String
    }

    public struct Integrity: Codable, Sendable, Equatable {
        public var maxStepsPerDay: Int
        public var flagStepsPerDay: Int
        public var maxPastDays: Int
        public var maxSustainedSpm: Double
    }

    public struct LeaderboardConfig: Codable, Sendable, Equatable {
        public var topN: Int
        public var cacheSeconds: Int
        public var metrics: [String]
    }
}

// MARK: - Loading

public enum FormulasError: Error, Equatable {
    case bundledResourceMissing
    case invalid(String)
}

extension Formulas {
    /// Decodes and validates formulas JSON (as served by `GET /v1/config`).
    public static func decode(from data: Data) throws -> Formulas {
        let formulas = try JSONDecoder().decode(Formulas.self, from: data)
        try formulas.validate()
        return formulas
    }

    /// Loads the copy of `shared/formulas.json` bundled inside StepquestKit.
    public static func loadBundled() throws -> Formulas {
        guard let url = Bundle.module.url(forResource: "formulas", withExtension: "json") else {
            throw FormulasError.bundledResourceMissing
        }
        return try decode(from: Data(contentsOf: url))
    }

    /// The bundled formulas. Crashing here means the app shipped a broken resource.
    public static let bundled: Formulas = {
        do { return try loadBundled() } catch { fatalError("Bundled formulas.json is invalid: \(error)") }
    }()

    /// Sanity checks so a bad remote config can't brick the game. Callers fall back to the bundled copy.
    public func validate() throws {
        guard !zones.isEmpty else { throw FormulasError.invalid("no zones") }
        guard zones.allSatisfy({ !$0.monsters.isEmpty && $0.lengthTiles > 0 && $0.gate.stepHp > 0 }) else {
            throw FormulasError.invalid("zone without monsters, length or gate HP")
        }
        guard !stride.tiers.isEmpty else { throw FormulasError.invalid("no cadence tiers") }
        guard !loot.rarities.isEmpty, loot.rarities.contains(where: { $0.weight > 0 }) else {
            throw FormulasError.invalid("no loot rarities")
        }
        guard !loot.slots.isEmpty else { throw FormulasError.invalid("no loot slots") }
        guard rarity(id: loot.gateGuaranteedRarity) != nil else {
            throw FormulasError.invalid("gateGuaranteedRarity not in rarities")
        }
        guard combat.encounterEveryTiles > 0, combat.heroAttacksPerSecond > 0, combat.monsterAttacksPerSecond > 0 else {
            throw FormulasError.invalid("combat rates must be positive")
        }
        guard idle.energyPerBonusTile > 0, idle.offlineCapHours >= 0 else {
            throw FormulasError.invalid("idle config invalid")
        }
        guard hero.maxLevel >= 1, hero.xpCurve.base > 0 else { throw FormulasError.invalid("hero config invalid") }
        guard stride.comboStepsPerLevel > 0 else { throw FormulasError.invalid("comboStepsPerLevel must be positive") }
    }

    // MARK: Lookups

    public func zone(id: Int) -> ZoneDefinition? { zones.first { $0.id == id } }

    public func nextZone(after id: Int) -> ZoneDefinition? {
        zones.filter { $0.id > id }.min { $0.id < $1.id }
    }

    public var firstZone: ZoneDefinition { zones.min { $0.id < $1.id }! }

    public func rarity(id: String) -> RarityDefinition? { loot.rarities.first { $0.id == id } }

    /// Highest cadence tier whose `minSpm` is at or below `spm`.
    public func tier(forSpm spm: Double) -> CadenceTier { stride.tier(forSpm: spm) }
}

extension Formulas.StrideConfig {
    public func tier(forSpm spm: Double) -> CadenceTier {
        let sorted = tiers.sorted { $0.minSpm < $1.minSpm }
        return sorted.last { spm >= $0.minSpm } ?? sorted[0]
    }
}
