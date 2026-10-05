// CoreSim/SeededRandom.swift: portable PRNG (SplitMix64). Never use SystemRandomNumberGenerator in Core.
public struct SeededRandom: RandomNumberGenerator, Sendable, Codable, Equatable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    /// The full generator state, so a world can be saved and resumed exactly.
    public var currentState: UInt64 { state }
    public init(state: UInt64) { self.state = state }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in [0, 1) with 53 bits of precision; the same on every platform.
    public mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    /// Standard normal as a sum of 12 uniforms minus 6 (arithmetic only, so bit-identical everywhere).
    public mutating func normal() -> Double { var s = 0.0; for _ in 0..<12 { s += unit() }; return s - 6.0 }
    /// Derive an independent stream, e.g. one per fight, so adding a draw in one place doesn't shift every other result.
    public func child(_ salt: UInt64) -> SeededRandom { SeededRandom(seed: state ^ (salt &* 0xD6E8_FEB8_6659_FD93)) }
}

// MARK: Convenience draws (all built on `unit()`, so they are portable and deterministic)

extension SeededRandom {
    /// Uniform in [low, high).
    public mutating func uniform(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }

    /// Uniform integer in the closed range.
    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        let count = range.upperBound - range.lowerBound + 1
        return range.lowerBound + min(count - 1, Int(unit() * Double(count)))
    }

    /// True with probability `p`.
    public mutating func chance(_ p: Double) -> Bool { unit() < p }

    /// A uniformly chosen element. The collection must not be empty.
    public mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }

    /// Index chosen with probability proportional to the weights (all >= 0, at least one > 0).
    public mutating func weightedIndex(_ weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        var roll = unit() * total
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 { return index }
        }
        return weights.count - 1
    }

    /// In-place Fisher-Yates shuffle with this generator (never use the standard library's `shuffled()` in Core).
    public mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) { items.swapAt(i, int(0...i)) }
    }
}
