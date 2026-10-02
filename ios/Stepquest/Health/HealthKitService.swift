import Foundation
import HealthKit
import Observation

/// One calendar day of HealthKit totals.
struct DailyHealthTotal: Equatable, Sendable {
    var day: String       // YYYY-MM-DD in the user's calendar
    var date: Date        // start of day
    var steps: Int
    var flights: Int

    var stepDay: StepDay { StepDay(day: day, steps: steps, flights: flights) }
}

/// Reads steps and flights climbed from HealthKit.
///
/// - Daily totals come from `HKStatisticsCollectionQuery` (cumulative sum, which de-duplicates iPhone + Watch).
/// - User-entered samples are excluded (`HKMetadataKeyWasUserEntered`) for anti-cheat (GAME_DESIGN.md §5).
/// - `HKObserverQuery` + background delivery wakes the app when new steps are written.
@MainActor
@Observable
final class HealthKitService {
    private(set) var todaySteps = 0
    private(set) var todayFlights = 0
    private(set) var weekSteps = 0
    private(set) var lastUpdated: Date?
    private(set) var authorizationRequested: Bool
    var lastError: String?

    /// Invoked (on the main actor) when the observer query fires. The app syncs + simulates in response.
    @ObservationIgnored var onNewData: (@MainActor () async -> Void)?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var observerQueries: [HKObserverQuery] = []
    private static let requestedKey = "healthAuthorizationRequested"

    private let stepType = HKQuantityType(.stepCount)
    private let flightsType = HKQuantityType(.flightsClimbed)

    init() {
        authorizationRequested = UserDefaults.standard.bool(forKey: Self.requestedKey)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// HealthKit never reveals whether *read* access was granted; we can only know we asked.
    func requestAuthorization() async {
        guard isAvailable else {
            lastError = "Health data isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType, flightsType])
            authorizationRequested = true
            UserDefaults.standard.set(true, forKey: Self.requestedKey)
            startObserving()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Queries

    /// Daily totals for the last `days` days including today (oldest first).
    func dailyTotals(days: Int, now: Date = .now, calendar: Calendar = .current) async throws -> [DailyHealthTotal] {
        guard isAvailable, authorizationRequested else { return [] }
        let todayStart = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: todayStart),
              let end = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return [] }

        async let stepSums = Self.dailySums(store: store, type: stepType, start: start, end: end, anchor: todayStart)
        async let flightSums = Self.dailySums(store: store, type: flightsType, start: start, end: end, anchor: todayStart)
        let steps = try await stepSums
        // Flights are optional (older devices / no barometer); don't fail the sync over them.
        let flights = (try? await flightSums) ?? [:]

        var totals: [DailyHealthTotal] = []
        var day = start
        while day < end {
            totals.append(DailyHealthTotal(
                day: DayKeyFormatter.string(for: day, calendar: calendar), date: day,
                steps: Int(steps[day] ?? 0), flights: Int(flights[day] ?? 0)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        if let today = totals.last {
            todaySteps = today.steps
            todayFlights = today.flights
        }
        weekSteps = Self.isoWeekSteps(totals, now: now)
        lastUpdated = now
        return totals
    }

    /// Steps since Monday 00:00 (ISO week) from the fetched days, for display.
    private static func isoWeekSteps(_ totals: [DailyHealthTotal], now: Date) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        guard let weekStart = iso.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return totals.filter { $0.date >= weekStart }.reduce(0) { $0 + $1.steps }
    }

    /// Runs an `HKStatisticsCollectionQuery` with one-day buckets. `nonisolated` so HealthKit's
    /// background-queue callbacks never touch main-actor state.
    private nonisolated static func dailySums(
        store: HKHealthStore, type: HKQuantityType, start: Date, end: Date, anchor: Date
    ) async throws -> [Date: Double] {
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let notUserEntered = NSPredicate(format: "metadata.%K != YES", HKMetadataKeyWasUserEntered)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, notUserEntered])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    // "No data available" just means zero steps.
                    if let hkError = error as? HKError, hkError.code == .errorNoData {
                        continuation.resume(returning: [:])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var sums: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        sums[statistics.startDate] = sum.doubleValue(for: .count())
                    }
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }
    }

    // MARK: Background delivery

    /// Registers observer queries and enables background delivery for steps and flights.
    /// Call on every launch (observer queries don't survive relaunch).
    func startObserving() {
        guard isAvailable, authorizationRequested, observerQueries.isEmpty else { return }
        for type in [stepType, flightsType] {
            let query = Self.makeObserverQuery(type: type) { [weak self] in
                await self?.onNewData?()
            }
            store.execute(query)
            observerQueries.append(query)
            Task { [store] in
                do {
                    try await store.enableBackgroundDelivery(for: type, frequency: .hourly)
                } catch {
                    print("HealthKit background delivery failed: \(error)")
                }
            }
        }
    }

    func stopObserving() {
        for query in observerQueries { store.stop(query) }
        observerQueries.removeAll()
    }

    private nonisolated static func makeObserverQuery(
        type: HKSampleType, onUpdate: @escaping @MainActor () async -> Void
    ) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task { @MainActor in
                await onUpdate()
                // Must be called so HealthKit keeps delivering in the background.
                completionHandler()
            }
        }
    }
}

/// `YYYY-MM-DD` for the API (same as StepquestKit.DayKey, kept local to avoid importing the kit here).
enum DayKeyFormatter {
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
