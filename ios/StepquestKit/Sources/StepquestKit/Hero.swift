import Foundation

/// A piece of gear. Its stat bonus is fixed at drop time so later balance changes never mutate owned items.
public struct Item: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var slot: EquipmentSlot
    public var rarityId: String
    public var zoneId: Int
    /// Rolled power before mapping to a stat (useful for comparing items in the same slot).
    public var power: Int
    public var bonus: StatBlock

    public init(id: String, name: String, slot: EquipmentSlot, rarityId: String, zoneId: Int, power: Int, bonus: StatBlock) {
        self.id = id
        self.name = name
        self.slot = slot
        self.rarityId = rarityId
        self.zoneId = zoneId
        self.power = power
        self.bonus = bonus
    }
}

/// The hero's three equipment slots.
public struct Equipment: Codable, Sendable, Equatable {
    public var weapon: Item?
    public var armor: Item?
    public var charm: Item?

    public init(weapon: Item? = nil, armor: Item? = nil, charm: Item? = nil) {
        self.weapon = weapon
        self.armor = armor
        self.charm = charm
    }

    public subscript(slot: EquipmentSlot) -> Item? {
        get {
            switch slot {
            case .weapon: weapon
            case .armor: armor
            case .charm: charm
            }
        }
        set {
            switch slot {
            case .weapon: weapon = newValue
            case .armor: armor = newValue
            case .charm: charm = newValue
            }
        }
    }

    public var all: [Item] { [weapon, armor, charm].compactMap { $0 } }

    public var totalBonus: StatBlock { all.reduce(.zero) { $0 + $1.bonus } }
}

/// The single hero.
public struct Hero: Codable, Sendable, Equatable {
    public var name: String
    public var level: Int
    /// XP accumulated toward the next level.
    public var xp: Int
    public var totalXP: Int
    public var gold: Int
    public var currentHP: Int
    public var equipment: Equipment
    public var inventory: [Item]

    public init(name: String = "Wanderer", formulas: Formulas) {
        self.name = name
        self.level = 1
        self.xp = 0
        self.totalXP = 0
        self.gold = 0
        self.equipment = Equipment()
        self.inventory = []
        self.currentHP = 0
        self.currentHP = maxHP(formulas)
    }

    /// Stats from level only (no gear).
    public func baseStats(_ formulas: Formulas) -> StatBlock {
        formulas.hero.base + formulas.hero.perLevel * (level - 1)
    }

    /// Effective stats: level growth + equipped gear.
    public func stats(_ formulas: Formulas) -> StatBlock {
        baseStats(formulas) + equipment.totalBonus
    }

    public func maxHP(_ formulas: Formulas) -> Int { max(1, stats(formulas).hp) }

    public func xpToNext(_ formulas: Formulas) -> Int { XPCurve.xpToNext(level: level, config: formulas.hero) }

    public var isAlive: Bool { currentHP > 0 }

    public func isMaxLevel(_ formulas: Formulas) -> Bool { level >= formulas.hero.maxLevel }

    /// Adds XP and resolves level-ups (full heal on each). Returns the number of levels gained.
    @discardableResult
    public mutating func gainXP(_ amount: Int, formulas: Formulas) -> Int {
        guard amount > 0 else { return 0 }
        totalXP += amount
        if isMaxLevel(formulas) { xp = 0; return 0 }
        xp += amount
        var gained = 0
        while !isMaxLevel(formulas) {
            let need = xpToNext(formulas)
            guard xp >= need else { break }
            xp -= need
            level += 1
            gained += 1
        }
        if isMaxLevel(formulas) { xp = 0 }
        if gained > 0 { currentHP = maxHP(formulas) }
        return gained
    }

    public mutating func heal(toFraction fraction: Double, formulas: Formulas) {
        currentHP = max(1, Int((Double(maxHP(formulas)) * fraction).rounded(.down)))
    }

    public mutating func healFull(_ formulas: Formulas) { currentHP = maxHP(formulas) }

    // MARK: Gear

    /// Equips an inventory item, moving any currently equipped item in that slot back to the inventory.
    @discardableResult
    public mutating func equip(itemId: String, formulas: Formulas) -> Bool {
        guard let index = inventory.firstIndex(where: { $0.id == itemId }) else { return false }
        let item = inventory.remove(at: index)
        if let previous = equipment[item.slot] { inventory.append(previous) }
        equipment[item.slot] = item
        clampHP(formulas)
        return true
    }

    @discardableResult
    public mutating func unequip(_ slot: EquipmentSlot, formulas: Formulas) -> Bool {
        guard let item = equipment[slot] else { return false }
        equipment[slot] = nil
        inventory.append(item)
        clampHP(formulas)
        return true
    }

    /// Adds a dropped item; equips it immediately when `autoEquip` is on and it beats the current one.
    /// Returns true when the item was equipped.
    @discardableResult
    public mutating func receive(_ item: Item, autoEquip: Bool, formulas: Formulas) -> Bool {
        inventory.append(item)
        let current = equipment[item.slot]
        if current == nil || (autoEquip && item.power > current!.power) {
            return equip(itemId: item.id, formulas: formulas)
        }
        return false
    }

    public mutating func discard(itemId: String) {
        inventory.removeAll { $0.id == itemId }
    }

    private mutating func clampHP(_ formulas: Formulas) {
        currentHP = min(currentHP, maxHP(formulas))
        if currentHP < 1 { currentHP = 1 }
    }
}

/// XP required per level: `floor(base * level ^ exponent)`.
public enum XPCurve {
    public static func xpToNext(level: Int, config: Formulas.HeroConfig) -> Int {
        let raw = config.xpCurve.base * pow(Double(max(1, level)), config.xpCurve.exponent)
        return max(1, Int(raw.rounded(.down)))
    }

    /// Total XP needed to go from level 1 to `level`.
    public static func totalXP(toReach level: Int, config: Formulas.HeroConfig) -> Int {
        guard level > 1 else { return 0 }
        return (1..<level).reduce(0) { $0 + xpToNext(level: $1, config: config) }
    }
}
