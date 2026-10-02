import StepquestKit
import XCTest
@testable import Stepquest

/// `@MainActor` per test (not on the class) so the tests also run under Linux XCTest discovery.
final class GameStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testFreshStoreStartsInFirstZone() async {
        let store = GameStore(config: ConfigStore(directory: directory), directory: directory)
        XCTAssertEqual(store.state.trail.frontierZoneId, 1)
        XCTAssertEqual(store.state.hero.level, 1)
    }

    @MainActor
    func testTickPersistsAndReloads() async {
        let t0 = Date(timeIntervalSince1970: 1_790_942_400)
        let config = ConfigStore(directory: directory)
        let store = GameStore(config: config, directory: directory, now: t0)
        store.tick(newSteps: 400, now: t0.addingTimeInterval(30 * 60))
        XCTAssertGreaterThan(store.state.trail.frontierTile, 0)

        let reloaded = GameStore(config: config, directory: directory, now: t0)
        XCTAssertEqual(reloaded.state, store.state)
    }

    @MainActor
    func testCorruptSaveIsMovedAside() async throws {
        try Data("not json".utf8).write(to: directory.appendingPathComponent("save.json"))
        let store = GameStore(config: ConfigStore(directory: directory), directory: directory)
        XCTAssertEqual(store.state.hero.level, 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("save.corrupt-") })
    }

    @MainActor
    func testHealthIngestUsesLedger() async {
        let t0 = Date()
        let store = GameStore(config: ConfigStore(directory: directory), directory: directory, now: t0)
        let today = DayKeyFormatter.string(for: t0)
        let first = store.ingestHealth([DailyHealthTotal(day: today, date: t0, steps: 1200, flights: 2)])
        let second = store.ingestHealth([DailyHealthTotal(day: today, date: t0, steps: 1500, flights: 2)])
        XCTAssertEqual(first, 1200)
        XCTAssertEqual(second, 300)
    }

    @MainActor
    func testAwaySummaryOnlyForLongAbsences() async {
        let t0 = Date(timeIntervalSince1970: 1_790_942_400)
        let store = GameStore(config: ConfigStore(directory: directory), directory: directory, now: t0)
        store.tick(now: t0.addingTimeInterval(60), presentAway: true)
        XCTAssertNil(store.awaySummary)
        store.tick(now: t0.addingTimeInterval(3 * 3600), presentAway: true)
        XCTAssertNotNil(store.awaySummary)
    }

    @MainActor
    func testConfigStoreFallsBackToBundled() async throws {
        try Data("{\"version\": 99}".utf8).write(to: directory.appendingPathComponent("formulas.json"))
        let config = ConfigStore(directory: directory)
        XCTAssertEqual(config.source, .bundled)
        XCTAssertEqual(config.formulas, Formulas.bundled)
    }
}
