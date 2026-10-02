import Foundation
import Observation
import StepquestKit
import UIKit

/// Runs a Stride Mode session: pulls live pedometer steps + cadence, feeds StepquestKit's `StrideEngine`,
/// mirrors events into the trail scene, fires haptics and the "look up!" safety nudge.
@MainActor
@Observable
final class StrideController {
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var engine: StrideEngine
    private(set) var monster: Monster?
    private(set) var lastEvents: [StrideEvent] = []
    private(set) var startedAt: Date?
    private(set) var showLookUp = false
    private(set) var flashTier = false

    /// Show "Look up!" after this long of continuous session time, then every interval.
    static let lookUpInterval: TimeInterval = 45
    static let tickInterval: Duration = .milliseconds(250)

    @ObservationIgnored weak var scene: TrailScene?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastLookUp = Date()
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private let light = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    @ObservationIgnored private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let notify = UINotificationFeedbackGenerator()

    private let store: GameStore
    private let pedometer: PedometerService

    init(store: GameStore, pedometer: PedometerService) {
        self.store = store
        self.pedometer = pedometer
        self.engine = StrideEngine(formulas: store.formulas)
    }

    // MARK: Session

    func start() {
        guard !isActive else { return }
        store.tick() // settle idle time up to now before live play takes over
        engine = StrideEngine(formulas: store.formulas)
        pedometer.updateFormulas(store.formulas)
        pedometer.start()
        isActive = true
        isPaused = false
        startedAt = .now
        lastTick = .now
        lastLookUp = .now
        lastSave = .now
        UIApplication.shared.isIdleTimerDisabled = true
        light.prepare()
        heavy.prepare()
        scene?.mode = .live
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: StrideController.tickInterval)
                self?.tick()
            }
        }
    }

    func stop() {
        guard isActive else { return }
        tick()
        loop?.cancel()
        loop = nil
        pedometer.stop()
        isActive = false
        isPaused = false
        monster = nil
        showLookUp = false
        UIApplication.shared.isIdleTimerDisabled = false
        scene?.mode = .idle
        store.save()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { showLookUp = false }
        lastTick = .now
    }

    func dismissLookUp() {
        showLookUp = false
        lastLookUp = .now
    }

    // MARK: Loop

    private func tick() {
        guard isActive else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        pedometer.refreshCadence(now: now)
        let steps = pedometer.drainSteps()
        // Paused: steps still count (they're real), but the hero doesn't fight.
        let effectiveDt = isPaused ? 0 : dt

        var events: [StrideEvent] = []
        store.mutate { state in
            events = engine.update(&state, dt: effectiveDt, newSteps: steps, spm: pedometer.spm, now: now)
        }
        monster = engine.monster
        if !events.isEmpty { lastEvents = Array((lastEvents + events).suffix(12)) }
        handle(events)

        if !isPaused, now.timeIntervalSince(lastLookUp) >= Self.lookUpInterval {
            showLookUp = true
            lastLookUp = now
            rigid.impactOccurred()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.showLookUp = false
            }
        }
        if now.timeIntervalSince(lastSave) > 15 {
            lastSave = now
            store.save()
        }
    }

    private func handle(_ events: [StrideEvent]) {
        for event in events {
            switch event {
            case let .tierChanged(tier):
                flashTier.toggle()
                if tier.combo { rigid.impactOccurred(intensity: 0.8) }
            case let .encounter(monster):
                scene?.liveEncounter(monster.definition)
            case let .heroHit(damage, crit, _):
                light.impactOccurred(intensity: crit ? 1 : 0.6)
                scene?.liveHeroHit(damage: damage, crit: crit)
            case let .monsterHit(damage, _):
                scene?.liveMonsterHit(damage: damage)
            case let .kill(reward):
                heavy.impactOccurred()
                scene?.liveKill(xp: reward.xp, gold: reward.gold)
                if let item = reward.item {
                    store.toast = "Found \(item.name)!"
                }
            case let .levelUp(level):
                notify.notificationOccurred(.success)
                store.levelUpBanner = level
            case .defeat:
                notify.notificationOccurred(.error)
                scene?.liveDefeat()
            case .reachedGate:
                notify.notificationOccurred(.warning)
                store.toast = "A Step Gate! Every stride strikes it."
            case let .gateHit(hit):
                scene?.liveGateHit(steps: Int(hit.dealt.rounded()))
                if hit.broken {
                    notify.notificationOccurred(.success)
                    if let zone = hit.newZone { store.zoneCard = zone }
                    store.toast = "The guardian falls!"
                }
            case .comboLevelUp:
                rigid.impactOccurred(intensity: 0.5)
            case .comboBroken:
                break
            }
        }
    }
}
