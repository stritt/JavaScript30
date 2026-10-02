import CoreMotion
import Foundation
import Observation
import StepquestKit

/// Live steps + rolling cadence for Stride Mode (CoreMotion `CMPedometer`).
///
/// Cadence is computed by StepquestKit's `CadenceTracker` over `cadenceWindowSeconds` and mapped to the
/// formulas' cadence tiers (Stroll / March / Rush / Frenzy).
@MainActor
@Observable
final class PedometerService {
    private(set) var isRunning = false
    private(set) var spm: Double = 0
    private(set) var tier: CadenceTier
    private(set) var sessionSteps = 0
    private(set) var authorizationDenied = false
    var lastError: String?
    #if DEBUG
    /// When set, fake steps are generated at this cadence (Simulator has no pedometer).
    private(set) var simulatedSpm: Double?
    #endif

    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private var tracker: CadenceTracker
    @ObservationIgnored private var formulas: Formulas
    @ObservationIgnored private var lastCumulative = 0
    @ObservationIgnored private var pendingSteps = 0
    @ObservationIgnored private let clockOrigin = Date()
    @ObservationIgnored private var simulationTask: Task<Void, Never>?

    init(formulas: Formulas) {
        self.formulas = formulas
        self.tracker = CadenceTracker(window: formulas.stride.cadenceWindowSeconds)
        self.tier = formulas.tier(forSpm: 0)
    }

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func updateFormulas(_ formulas: Formulas) {
        self.formulas = formulas
        tracker.window = max(1, formulas.stride.cadenceWindowSeconds)
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        resetSession()
        isRunning = true
        authorizationDenied = CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted
        #if DEBUG
        if simulatedSpm != nil { startSimulation(); return }
        #endif
        guard isAvailable else {
            lastError = "Step counting isn't available on this device."
            return
        }
        pedometer.startUpdates(from: Date(), withHandler: Self.makeHandler { [weak self] steps, error in
            self?.handle(cumulativeSteps: steps, error: error)
        })
    }

    func stop() {
        guard isRunning else { return }
        pedometer.stopUpdates()
        simulationTask?.cancel()
        simulationTask = nil
        isRunning = false
        spm = 0
        tier = formulas.tier(forSpm: 0)
    }

    /// Steps received since the last call. Stride Mode consumes these every tick.
    func drainSteps() -> Int {
        defer { pendingSteps = 0 }
        return pendingSteps
    }

    /// Recomputes cadence at `now` so it decays when the walker stops (CMPedometer goes quiet).
    func refreshCadence(now: Date = .now) {
        let value = tracker.spm(at: now.timeIntervalSince(clockOrigin))
        spm = value
        tier = formulas.tier(forSpm: value)
    }

    // MARK: Updates

    private func handle(cumulativeSteps: Int?, error: Error?) {
        if let error {
            let nsError = error as NSError
            if nsError.domain == CMErrorDomain && nsError.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                authorizationDenied = true
            }
            lastError = error.localizedDescription
            return
        }
        guard let cumulativeSteps else { return }
        record(cumulativeSteps: cumulativeSteps)
    }

    private func record(cumulativeSteps: Int) {
        let delta = max(0, cumulativeSteps - lastCumulative)
        lastCumulative = cumulativeSteps
        pendingSteps += delta
        sessionSteps += delta
        tracker.record(cumulativeSteps: cumulativeSteps, at: Date().timeIntervalSince(clockOrigin))
        refreshCadence()
    }

    private func resetSession() {
        tracker.reset()
        lastCumulative = 0
        pendingSteps = 0
        sessionSteps = 0
        spm = 0
        lastError = nil
    }

    /// CMPedometer calls back on a private queue; hop to the main actor with plain values.
    private nonisolated static func makeHandler(
        _ onUpdate: @escaping @MainActor (Int?, Error?) -> Void
    ) -> CMPedometerHandler {
        { data, error in
            let steps = data?.numberOfSteps.intValue
            Task { @MainActor in onUpdate(steps, error) }
        }
    }

    // MARK: Debug simulation

    #if DEBUG
    func setSimulatedCadence(_ spm: Double?) {
        simulatedSpm = spm
        if isRunning {
            pedometer.stopUpdates()
            simulationTask?.cancel()
            if spm != nil {
                startSimulation()
            } else if isAvailable {
                lastCumulative = 0
                tracker.reset()
                pedometer.startUpdates(from: Date(), withHandler: Self.makeHandler { [weak self] steps, error in
                    self?.handle(cumulativeSteps: steps, error: error)
                })
            }
        }
    }

    private func startSimulation() {
        simulationTask?.cancel()
        lastCumulative = 0
        tracker.reset()
        simulationTask = Task { [weak self] in
            var cumulative = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let rate = self.simulatedSpm else { return }
                cumulative += rate / 120 // half a second of steps
                self.record(cumulativeSteps: Int(cumulative))
            }
        }
    }
    #endif
}
