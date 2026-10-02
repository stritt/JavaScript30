import Foundation

/// SplitMix64: tiny, fast, seedable PRNG. The state is persisted inside `GameState`
/// so the offline simulation is fully deterministic and reproducible.
///
/// The helpers below (`nextUnit`, `nextInt(below:)`) are implemented here rather than via
/// `Int.random(in:using:)` so results never depend on the standard library's sampling algorithm.
public struct SplitMix64: RandomNumberGenerator, Sendable, Equatable, Hashable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Uniform integer in [0, bound). `bound` must be > 0.
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let b = UInt64(bound)
        // Rejection sampling removes modulo bias.
        let limit = UInt64.max - (UInt64.max % b)
        var x = next()
        while x >= limit { x = next() }
        return Int(x % b)
    }

    /// True with probability `p`.
    public mutating func chance(_ p: Double) -> Bool {
        if p <= 0 { return false }
        if p >= 1 { return true }
        return nextUnit() < p
    }

    /// Picks an element. `items` must be non-empty.
    public mutating func pick<T>(_ items: [T]) -> T {
        items[nextInt(below: items.count)]
    }

    /// Weighted pick. Returns nil when all weights are <= 0.
    public mutating func weightedPick<T>(_ items: [T], weight: (T) -> Double) -> T? {
        let total = items.reduce(0.0) { $0 + max(0, weight($1)) }
        guard total > 0 else { return nil }
        var roll = nextUnit() * total
        for item in items {
            let w = max(0, weight(item))
            if roll < w { return item }
            roll -= w
        }
        return items.last { weight($0) > 0 }
    }

    /// 16-hex-char identifier drawn from the stream (deterministic item ids).
    public mutating func nextIdentifier() -> String {
        let hex = String(next(), radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

// Encoded as a hex string: some JSON stacks lose precision on UInt64 values above 2^53.
extension SplitMix64: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = UInt64(raw, radix: 16) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad rng state"))
        }
        self.state = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(state, radix: 16))
    }
}
