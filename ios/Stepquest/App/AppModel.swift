import BackgroundTasks
import Foundation
import Observation
import StepquestKit

/// Composition root: owns services and runs the sync loop
/// (HealthKit → StepLedger → OfflineSimulator → POST /v1/steps → PATCH /v1/me).
@MainActor
@Observable
final class AppModel {
    static let refreshTaskId = "app.stepquest.ios.refresh"

    let config: ConfigStore
    let store: GameStore
    let health: HealthKitService
    let pedometer: PedometerService
    let api: APIClient
    let auth: AuthService

    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    var syncError: String?

    @ObservationIgnored private var lastReported: (level: Int, zone: Int)?
    @ObservationIgnored private var bootstrapped = false

    init() {
        let config = ConfigStore()
        let api = APIClient()
        self.config = config
        self.api = api
        self.store = GameStore(config: config)
        self.health = HealthKitService()
        self.pedometer = PedometerService(formulas: config.formulas)
        self.auth = AuthService(api: api)
        health.onNewData = { [weak self] in await self?.sync(presentAway: false) }
    }

    // MARK: Lifecycle

    /// First launch work (after the boot screen).
    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        health.startObserving()
        await sync(presentAway: true)
        if await config.refresh(using: api) {
            pedometer.updateFormulas(config.formulas)
        }
        await auth.refreshMe()
        scheduleAppRefresh()
    }

    func handleForeground() async {
        guard bootstrapped else { return }
        await sync(presentAway: true)
    }

    func handleBackground() {
        store.tick()
        scheduleAppRefresh()
    }

    /// BGAppRefreshTask handler (registered via `.backgroundTask(.appRefresh(...))`).
    func backgroundRefresh() async {
        await sync(presentAway: false)
        scheduleAppRefresh()
    }

    // MARK: Sync

    /// Pulls HealthKit totals, credits new steps, simulates idle progress, then reports to the backend.
    func sync(presentAway: Bool) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var totals: [DailyHealthTotal] = []
        do {
            totals = try await health.dailyTotals(days: config.formulas.integrity.maxPastDays)
        } catch {
            syncError = error.localizedDescription
        }
        let newSteps = store.ingestHealth(totals)
        store.tick(newSteps: newSteps, presentAway: presentAway)
        lastSync = .now

        guard auth.isSignedIn else { return }
        do {
            if !totals.isEmpty {
                try await api.uploadSteps(totals.map(\.stepDay))
            }
            try await reportProgress()
            syncError = nil
        } catch {
            syncError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// `PATCH /v1/me` with hero level and deepest zone (server never lets these decrease).
    func reportProgress() async throws {
        let level = store.state.hero.level
        let zone = store.state.trail.frontierZoneId
        if let last = lastReported, last.level == level, last.zone == zone { return }
        try await auth.update(PatchMeRequest(heroLevel: level, zone: zone))
        lastReported = (level, zone)
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
