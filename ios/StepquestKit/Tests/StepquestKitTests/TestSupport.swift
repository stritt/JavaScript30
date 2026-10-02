import Foundation
import XCTest
@testable import StepquestKit

enum Fixtures {
    static let formulas: Formulas = Formulas.bundled

    /// 2026-10-02 12:00:00 UTC
    static let t0 = Date(timeIntervalSince1970: 1_790_942_400)

    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func newGame(seed: UInt64 = 42, formulas: Formulas = Fixtures.formulas) -> GameState {
        GameState(formulas: formulas, seed: seed, now: t0, calendar: utc)
    }

    /// Formulas with an absurdly strong monster so every fight is lost.
    static var deadlyFormulas: Formulas {
        var f = formulas
        f.zones[0].monsters = [MonsterDefinition(id: "dragon", name: "Test Dragon", hp: 100_000, atk: 1_000, def: 1_000, xp: 1, gold: 1)]
        return f
    }

    /// Formulas with a very long first zone (for testing caps without hitting the gate).
    static var longZoneFormulas: Formulas {
        var f = formulas
        f.zones[0].lengthTiles = 100_000
        return f
    }

    /// Puts the hero at the frontier gate of the current zone.
    static func atGate(_ state: inout GameState, formulas: Formulas = Fixtures.formulas) {
        let tiles = state.tilesToGate(formulas)
        _ = state.walk(tiles: tiles + 1, formulas: formulas, now: t0)
        state.trail.encounterProgress = 0
    }
}
