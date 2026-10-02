import Foundation

/// The Gate Guardian at the end of a zone. It has a real-steps HP bar.
///
/// Only steps taken *after* the gate is reached count (the gate only exists from that moment), idle
/// trickle never damages it, and Stride Mode steps count `gateStepMultiplier` (1.5x).
public struct StepGate: Codable, Sendable, Equatable {
    public var zoneId: Int
    public var name: String
    public var stepHP: Int
    public var damage: Double
    public var reachedAt: Date
    public var brokenAt: Date?

    public init(zone: ZoneDefinition, reachedAt: Date) {
        self.zoneId = zone.id
        self.name = zone.gate.name
        self.stepHP = zone.gate.stepHp
        self.damage = 0
        self.reachedAt = reachedAt
        self.brokenAt = nil
    }

    public var isBroken: Bool { damage >= Double(stepHP) }

    /// Steps of damage still needed (rounded up).
    public var remaining: Int { max(0, Int((Double(stepHP) - damage).rounded(.up))) }

    /// 0...1 fraction of HP removed.
    public var progress: Double { stepHP > 0 ? min(1, damage / Double(stepHP)) : 1 }

    /// Applies real steps. Returns damage actually dealt (never more than remaining HP).
    @discardableResult
    public mutating func apply(steps: Int, stride: Bool, config: Formulas.StrideConfig, at date: Date) -> Double {
        guard steps > 0, !isBroken else { return 0 }
        let raw = Double(steps) * (stride ? config.gateStepMultiplier : 1)
        let dealt = min(raw, Double(stepHP) - damage)
        damage += dealt
        if isBroken && brokenAt == nil { brokenAt = date }
        return dealt
    }

    /// Real steps (non-stride) still needed.
    public var stepsToBreak: Int { remaining }

    /// Stride Mode steps still needed.
    public func strideStepsToBreak(_ config: Formulas.StrideConfig) -> Int {
        Int((Double(remaining) / config.gateStepMultiplier).rounded(.up))
    }
}
