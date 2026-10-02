import StepquestKit
import SwiftUI

/// Equipment slots, stats, and the satchel of dropped gear (colored by rarity). Tap to equip.
struct InventoryView: View {
    @Environment(GameStore.self) private var store
    @State private var sort: Sort = .power
    @State private var pendingDiscard: Item?

    enum Sort: String, CaseIterable, Identifiable {
        case power = "Power", rarity = "Rarity", slot = "Slot"
        var id: String { rawValue }
    }

    var body: some View {
        let formulas = store.formulas
        let hero = store.state.hero
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        ForEach(EquipmentSlot.allCases) { slot in
                            SlotCard(slot: slot, item: hero.equipment[slot]) {
                                store.unequip(slot)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    statsRow(hero: hero, formulas: formulas)
                        .listRowBackground(Color.clear)
                } header: {
                    sectionHeader("Equipped")
                }

                Section {
                    Toggle(isOn: Binding(get: { store.state.autoEquip }, set: { store.setAutoEquip($0) })) {
                        Text("Auto-equip upgrades").font(ParchmentTheme.body(.subheadline, weight: .semibold))
                    }
                    .tint(ParchmentTheme.crimson)
                    .listRowBackground(ParchmentTheme.parchmentLight.opacity(0.6))
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    if hero.inventory.isEmpty {
                        Text("Your satchel is empty. Defeat foes on the trail to find gear.")
                            .font(ParchmentTheme.body(.footnote))
                            .foregroundStyle(ParchmentTheme.inkSoft)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(sorted(hero.inventory, formulas: formulas)) { item in
                        Button {
                            store.equip(item)
                        } label: {
                            ItemRow(item: item, equipped: hero.equipment[item.slot], formulas: formulas)
                        }
                        .listRowBackground(ParchmentTheme.parchmentLight.opacity(0.6))
                        .swipeActions {
                            Button(role: .destructive) { pendingDiscard = item } label: { Label("Discard", systemImage: "trash") }
                        }
                    }
                } header: {
                    sectionHeader("Satchel (\(hero.inventory.count))")
                }
            }
            .scrollContentBackground(.hidden)
            .parchmentBackground()
            .navigationTitle("Gear")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Discard this item?", isPresented: Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } }),
                                titleVisibility: .visible, presenting: pendingDiscard) { item in
                Button("Discard \(item.name)", role: .destructive) { store.discard(item) }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(ParchmentTheme.display(13))
            .tracking(1.5)
            .foregroundStyle(ParchmentTheme.goldDeep)
    }

    private func statsRow(hero: Hero, formulas: Formulas) -> some View {
        let total = hero.stats(formulas)
        let base = hero.baseStats(formulas)
        return HStack {
            statCell("HP", total.hp, bonus: total.hp - base.hp)
            statCell("ATK", total.atk, bonus: total.atk - base.atk)
            statCell("DEF", total.def, bonus: total.def - base.def)
            statCell("LV", hero.level, bonus: 0)
        }
        .parchmentPanel(padding: 8)
    }

    private func statCell(_ label: String, _ value: Int, bonus: Int) -> some View {
        VStack(spacing: 1) {
            Text(label).font(ParchmentTheme.display(11)).foregroundStyle(ParchmentTheme.inkSoft)
            Text("\(value)").font(ParchmentTheme.numeric(20)).foregroundStyle(ParchmentTheme.ink)
            Text(bonus > 0 ? "+\(bonus) gear" : " ")
                .font(ParchmentTheme.body(.caption2))
                .foregroundStyle(ParchmentTheme.forestGreen)
        }
        .frame(maxWidth: .infinity)
    }

    private func sorted(_ items: [Item], formulas: Formulas) -> [Item] {
        let rarityRank = Dictionary(uniqueKeysWithValues: formulas.loot.rarities.enumerated().map { ($1.id, $0) })
        switch sort {
        case .power: return items.sorted { ($0.power, $0.zoneId) > ($1.power, $1.zoneId) }
        case .rarity: return items.sorted { (rarityRank[$0.rarityId] ?? 0, $0.power) > (rarityRank[$1.rarityId] ?? 0, $1.power) }
        case .slot: return items.sorted { ($0.slot.rawValue, -$0.power) < ($1.slot.rawValue, -$1.power) }
        }
    }
}

private struct SlotCard: View {
    let slot: EquipmentSlot
    let item: Item?
    var onUnequip: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: SlotIcon.name(slot))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(item.map { ParchmentTheme.rarityColor($0.rarityId) } ?? ParchmentTheme.inkSoft.opacity(0.5))
                .frame(height: 30)
            Text(item?.name ?? slot.rawValue.capitalized)
                .font(ParchmentTheme.body(.caption, weight: .semibold))
                .foregroundStyle(item == nil ? ParchmentTheme.inkSoft : ParchmentTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(item.map { ItemRow.bonusText($0) } ?? "Empty")
                .font(ParchmentTheme.numeric(11, weight: .bold))
                .foregroundStyle(ParchmentTheme.forestGreen)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(ParchmentTheme.parchmentLight))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.map { ParchmentTheme.rarityColor($0.rarityId) } ?? ParchmentTheme.goldDeep, lineWidth: 2))
        .contextMenu {
            if item != nil { Button("Unequip", systemImage: "arrow.down.to.line", action: onUnequip) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ItemRow: View {
    let item: Item
    let equipped: Item?
    let formulas: Formulas

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: SlotIcon.name(item.slot))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ParchmentTheme.rarityColor(item.rarityId))
                .frame(width: 34, height: 34)
                .background(Circle().fill(ParchmentTheme.rarityColor(item.rarityId).opacity(0.15)))
                .overlay(Circle().stroke(ParchmentTheme.rarityColor(item.rarityId), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(ParchmentTheme.body(.subheadline, weight: .bold))
                    .foregroundStyle(ParchmentTheme.rarityColor(item.rarityId))
                Text("\(formulas.rarity(id: item.rarityId)?.name ?? item.rarityId.capitalized) \(item.slot.rawValue) · Chapter \(Roman.numeral(item.zoneId))")
                    .font(ParchmentTheme.body(.caption2))
                    .foregroundStyle(ParchmentTheme.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.bonusText(item)).font(ParchmentTheme.numeric(14))
                    .foregroundStyle(ParchmentTheme.ink)
                if let delta = delta {
                    Text(delta > 0 ? "▲\(delta)" : delta < 0 ? "▼\(-delta)" : "=")
                        .font(ParchmentTheme.numeric(11, weight: .bold))
                        .foregroundStyle(delta > 0 ? ParchmentTheme.forestGreen : delta < 0 ? ParchmentTheme.crimson : ParchmentTheme.inkSoft)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to equip")
    }

    private var delta: Int? {
        guard let equipped else { return nil }
        return item.power - equipped.power
    }

    static func bonusText(_ item: Item) -> String {
        var parts: [String] = []
        if item.bonus.atk != 0 { parts.append("+\(item.bonus.atk) ATK") }
        if item.bonus.def != 0 { parts.append("+\(item.bonus.def) DEF") }
        if item.bonus.hp != 0 { parts.append("+\(item.bonus.hp) HP") }
        return parts.joined(separator: " ")
    }
}

enum SlotIcon {
    static func name(_ slot: EquipmentSlot) -> String {
        switch slot {
        case .weapon: "bolt.horizontal.fill"
        case .armor: "shield.lefthalf.filled"
        case .charm: "seal.fill"
        }
    }
}
