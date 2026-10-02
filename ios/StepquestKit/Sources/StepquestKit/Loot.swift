import Foundation

/// Rolls gear drops from `formulas.loot`.
///
/// Power = `baseStatPerZone * zoneId * rarity.statMultiplier` (rounded, min 1).
/// Mapping to stats: weapon -> ATK, armor -> DEF, charm -> HP (power * hero.perLevel.hp / hero.perLevel.atk,
/// i.e. charms are worth about as many "levels" of HP as a weapon is of ATK).
public struct LootGenerator: Sendable {
    public let formulas: Formulas

    public init(formulas: Formulas) {
        self.formulas = formulas
    }

    /// Normal kill drop: `dropChance`, then weighted rarity and a random slot.
    public func rollDrop(zoneId: Int, rng: inout SplitMix64) -> Item? {
        guard rng.chance(formulas.loot.dropChance) else { return nil }
        let rarity = rollRarity(rng: &rng)
        return makeItem(zoneId: zoneId, rarity: rarity, rng: &rng)
    }

    /// Guaranteed gate-guardian drop at `gateGuaranteedRarity`.
    public func gateReward(zoneId: Int, rng: inout SplitMix64) -> Item {
        let rarity = formulas.rarity(id: formulas.loot.gateGuaranteedRarity) ?? rollRarity(rng: &rng)
        return makeItem(zoneId: zoneId, rarity: rarity, rng: &rng)
    }

    public func rollRarity(rng: inout SplitMix64) -> RarityDefinition {
        rng.weightedPick(formulas.loot.rarities) { $0.weight } ?? formulas.loot.rarities[0]
    }

    public func makeItem(zoneId: Int, rarity: RarityDefinition, slot: EquipmentSlot? = nil, rng: inout SplitMix64) -> Item {
        let slot = slot ?? rng.pick(formulas.loot.slots)
        let power = Self.power(zoneId: zoneId, rarity: rarity, config: formulas.loot)
        let palette = formulas.zone(id: zoneId)?.palette ?? .unknown
        let name = ItemNames.name(slot: slot, palette: palette, rarity: rarity, rng: &rng)
        return Item(
            id: rng.nextIdentifier(), name: name, slot: slot, rarityId: rarity.id, zoneId: zoneId,
            power: power, bonus: bonus(slot: slot, power: power))
    }

    public static func power(zoneId: Int, rarity: RarityDefinition, config: Formulas.LootConfig) -> Int {
        max(1, Int((config.baseStatPerZone * Double(max(1, zoneId)) * rarity.statMultiplier).rounded()))
    }

    public func bonus(slot: EquipmentSlot, power: Int) -> StatBlock {
        switch slot {
        case .weapon: return StatBlock(atk: power)
        case .armor: return StatBlock(def: power)
        case .charm:
            let per = formulas.hero.perLevel
            let ratio = per.atk > 0 ? max(1, per.hp / per.atk) : 1
            return StatBlock(hp: power * ratio)
        }
    }
}

/// Original flavor names for generated gear.
enum ItemNames {
    static let nouns: [EquipmentSlot: [String]] = [
        .weapon: ["Blade", "Hatchet", "Spear", "Cudgel", "Saber"],
        .armor: ["Jerkin", "Mail", "Cuirass", "Coat", "Tabard"],
        .charm: ["Amulet", "Ring", "Talisman", "Locket", "Brooch"],
    ]

    static let adjectives: [ZonePalette: [String]] = [
        .meadow: ["Mossy", "Shepherd's", "Hedgerow", "Clover"],
        .forest: ["Ashen", "Lantern", "Barkwood", "Hollow"],
        .desert: ["Brass", "Sunbaked", "Mirage", "Glass"],
        .unknown: ["Wayfarer's", "Old", "Pilgrim's"],
    ]

    static func name(slot: EquipmentSlot, palette: ZonePalette, rarity: RarityDefinition, rng: inout SplitMix64) -> String {
        let adjective = rng.pick(adjectives[palette] ?? adjectives[.unknown]!)
        let noun = rng.pick(nouns[slot] ?? ["Relic"])
        switch rarity.id {
        case "legendary": return "\(adjective) \(noun) of Legend"
        case "epic": return "Gilded \(adjective) \(noun)"
        default: return "\(adjective) \(noun)"
        }
    }
}
