import Foundation
import Observation
import StepquestKit

/// Owns the persisted `GameState` (a JSON file in Application Support) and runs the deterministic
/// `OfflineSimulator` on launch, on foreground and on a slow timer while the app is open.
///
/// GAME_DESIGN.md §6a suggests SwiftData; a single Codable JSON document is simpler and just as robust for one
/// save slot (atomic writes, a corrupt file is moved aside instead of crashing). The server stays the
/// source of truth for anything competitive.
@MainActor
@Observable
final class GameStore {
    private(set) var state: GameState

    // Presentation state driven by game events.
    var awaySummary: OfflineSummary?
    var levelUpBanner: Int?
    var zoneCard: ZoneDefinition?
    var toast: String?

    @ObservationIgnored let config: ConfigStore
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    @ObservationIgnored private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Only show "While you were away" for absences longer than this.
    static let awayThreshold: TimeInterval = 5 * 60

    init(config: ConfigStore, directory: URL = FileLocations.appSupport, now: Date = .now) {
        self.config = config
        let url = directory.appendingPathComponent("save.json")
        self.fileURL = url
        let loader = JSONDecoder()
        loader.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url) {
            do {
                state = try loader.decode(GameState.self, from: data)
            } catch {
                // Keep the broken save for debugging rather than silently overwriting it.
                let aside = directory.appendingPathComponent("save.corrupt-\(Int(now.timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: url, to: aside)
                state = GameState(formulas: config.formulas, seed: UInt64.random(in: .min ... .max), now: now)
            }
        } else {
            state = GameState(formulas: config.formulas, seed: UInt64.random(in: .min ... .max), now: now)
        }
    }

    var formulas: Formulas { config.formulas }

    // MARK: Simulation

    /// Converts HealthKit daily totals into new steps via the save's `StepLedger` (no double counting,
    /// stride steps already credited are subtracted). Returns the new steps.
    func ingestHealth(_ totals: [DailyHealthTotal]) -> Int {
        var dict: [String: Int] = [:]
        for t in totals { dict[t.day] = t.steps }
        return state.ledger.ingest(dailyTotals: dict)
    }

    /// Advances idle progress to `now`. Fires level-up / zone-card / away presentation as needed.
    @discardableResult
    func tick(newSteps: Int = 0, now: Date = .now, presentAway: Bool = false) -> OfflineSummary {
        let summary = OfflineSimulator(formulas: formulas).catchUp(&state, newSteps: newSteps, now: now)
        present(summary, presentAway: presentAway)
        save()
        return summary
    }

    private func present(_ summary: OfflineSummary, presentAway: Bool) {
        if summary.levelUps > 0 { levelUpBanner = summary.endLevel }
        if let zoneId = summary.zonesEntered.last, let zone = formulas.zone(id: zoneId) { zoneCard = zone }
        if presentAway, summary.elapsedSeconds >= Self.awayThreshold, !summary.isEmpty {
            awaySummary = summary
        } else if summary.reachedGate, let gate = state.gate {
            toast = "\(gate.name) blocks the road!"
        }
    }

    /// Mutates state (used by Stride Mode and player actions) and saves.
    func mutate(_ body: (inout GameState) -> Void) {
        body(&state)
        save()
    }

    // MARK: Player actions

    func equip(_ item: Item) { mutate { $0.equip(itemId: item.id, formulas: formulas) } }

    func unequip(_ slot: EquipmentSlot) { mutate { $0.unequip(slot, formulas: formulas) } }

    func discard(_ item: Item) { mutate { $0.hero.discard(itemId: item.id) } }

    func setAutoEquip(_ on: Bool) { mutate { $0.autoEquip = on } }

    /// Grind a cleared zone, or `nil` to return to the frontier.
    @discardableResult
    func travel(to zoneId: Int?) -> Bool {
        tick()
        var ok = false
        mutate { ok = $0.travel(to: zoneId, formulas: formulas) }
        if ok, let zoneId, let zone = formulas.zone(id: zoneId) { zoneCard = zone }
        if ok, zoneId == nil { zoneCard = state.frontierZone(formulas) }
        return ok
    }

    #if DEBUG
    func resetGame() {
        state = GameState(formulas: formulas, seed: UInt64.random(in: .min ... .max), now: .now)
        save()
        zoneCard = state.frontierZone(formulas)
    }
    #endif

    // MARK: Persistence

    func save() {
        do {
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Save failed: \(error)")
        }
    }
}
