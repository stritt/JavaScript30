import Foundation

/// Rolling cadence (steps per minute) over `cadenceWindowSeconds`, fed by cumulative pedometer counts.
///
/// Pure value type so it can be unit-tested; `PedometerService` on device feeds it CMPedometer updates.
public struct CadenceTracker: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public var time: TimeInterval
        public var cumulativeSteps: Int
    }

    public var window: TimeInterval
    public private(set) var samples: [Sample] = []

    public init(window: TimeInterval) {
        self.window = max(1, window)
    }

    /// Records the cumulative step count reported at `time` (seconds, any monotonic clock).
    public mutating func record(cumulativeSteps: Int, at time: TimeInterval) {
        if let last = samples.last {
            if time < last.time { return }
            if cumulativeSteps < last.cumulativeSteps {
                // Pedometer restarted: start a fresh series.
                samples.removeAll()
            }
        }
        samples.append(Sample(time: time, cumulativeSteps: cumulativeSteps))
        prune(now: time)
    }

    public mutating func reset() { samples.removeAll() }

    /// Steps per minute over the trailing window ending at `now`. Decays toward 0 when updates stop.
    public func spm(at now: TimeInterval) -> Double {
        guard let latest = samples.last else { return 0 }
        let windowStart = now - window
        // Baseline: the latest sample at or before the window start, else the earliest we have.
        let baseline = samples.last { $0.time <= windowStart } ?? samples[0]
        let span = now - baseline.time
        guard span >= 1 else { return 0 }
        let steps = latest.cumulativeSteps - baseline.cumulativeSteps
        guard steps > 0 else { return 0 }
        // If the latest sample is itself older than the window, the walker stopped.
        if latest.time < windowStart { return 0 }
        return Double(steps) / span * 60
    }

    private mutating func prune(now: TimeInterval) {
        let windowStart = now - window
        // Keep one sample at/before the window start as the baseline.
        if let idx = samples.lastIndex(where: { $0.time <= windowStart }), idx > 0 {
            samples.removeFirst(idx)
        }
    }
}

/// Stride Mode combo meter: grows while walking in a combo-enabled tier (Rush / Frenzy),
/// resets when cadence drops to a tier without combos.
public struct Combo: Codable, Sendable, Equatable {
    public var steps: Int = 0
    public var bestLevel: Int = 0

    public init() {}

    public func level(_ config: Formulas.StrideConfig) -> Int { steps / max(1, config.comboStepsPerLevel) }

    /// Extra damage fraction, capped at `comboMaxBonus`.
    public func bonus(_ config: Formulas.StrideConfig) -> Double {
        min(config.comboMaxBonus, Double(level(config)) * config.comboBonusPerLevel)
    }

    /// 0...1 progress toward the next combo level.
    public func progressToNextLevel(_ config: Formulas.StrideConfig) -> Double {
        let per = max(1, config.comboStepsPerLevel)
        return Double(steps % per) / Double(per)
    }

    public func isMaxed(_ config: Formulas.StrideConfig) -> Bool { bonus(config) >= config.comboMaxBonus }

    /// Returns the number of combo levels gained (0 or more), or -1 if the combo broke.
    @discardableResult
    public mutating func register(steps newSteps: Int, tier: CadenceTier, config: Formulas.StrideConfig) -> Int {
        guard tier.combo else {
            let broke = steps > 0
            steps = 0
            return broke ? -1 : 0
        }
        guard newSteps > 0 else { return 0 }
        let before = level(config)
        steps += newSteps
        let after = level(config)
        bestLevel = max(bestLevel, after)
        return after - before
    }
}
