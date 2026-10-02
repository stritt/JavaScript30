import Foundation

/// Turns HealthKit *daily totals* into *new steps since last time*, so steps are never counted twice.
///
/// - Days before `startDay` (the day the save was created) are ignored: no windfall from old history.
/// - Steps already applied live in Stride Mode are recorded as `strideCredit` and subtracted from the next
///   HealthKit delta (those same steps show up in HealthKit later).
/// - Totals that go down (HealthKit corrections) never produce negative steps.
public struct StepLedger: Codable, Sendable, Equatable {
    public var startDay: String
    public var lastSeenByDay: [String: Int]
    public var strideCredit: Int

    public init(startDay: String) {
        self.startDay = startDay
        self.lastSeenByDay = [:]
        self.strideCredit = 0
    }

    /// Ingests daily totals (`"YYYY-MM-DD": steps`) and returns new steps not yet credited to the game.
    public mutating func ingest(dailyTotals: [String: Int]) -> Int {
        var delta = 0
        for (day, total) in dailyTotals where day >= startDay {
            let seen = lastSeenByDay[day] ?? 0
            if total > seen {
                delta += total - seen
                lastSeenByDay[day] = total
            }
        }
        let fromCredit = min(delta, strideCredit)
        strideCredit -= fromCredit
        prune()
        return delta - fromCredit
    }

    /// Called when Stride Mode applies live pedometer steps directly.
    public mutating func recordStrideSteps(_ steps: Int) {
        guard steps > 0 else { return }
        strideCredit += steps
    }

    private mutating func prune() {
        guard lastSeenByDay.count > 21 else { return }
        let keep = Set(lastSeenByDay.keys.sorted().suffix(21))
        lastSeenByDay = lastSeenByDay.filter { keep.contains($0.key) }
    }
}

/// `YYYY-MM-DD` keys in the user's calendar (matches the API's `day` format).
public enum DayKey {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
