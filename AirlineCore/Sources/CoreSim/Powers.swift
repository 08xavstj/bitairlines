// CoreSim/Powers.swift: fractional powers built only from multiplication and square roots (exact and identical on every platform).
public enum Powers {
    /// x raised to k/8 for k in 0...16 (x must be >= 0). For example `eighths(pop, 7)` is pop^0.875.
    public static func eighths(_ x: Double, _ k: Int) -> Double {
        let r1 = x.squareRoot()
        let r2 = r1.squareRoot()
        let r3 = r2.squareRoot()
        var out = 1.0
        for _ in 0..<(k / 8) { out *= x }
        let frac = k % 8
        if frac & 4 != 0 { out *= r1 }
        if frac & 2 != 0 { out *= r2 }
        if frac & 1 != 0 { out *= r3 }
        return out
    }

    /// x raised to 1.5 (x >= 0), used for price elasticity.
    public static func oneAndAHalf(_ x: Double) -> Double { x * x.squareRoot() }
}
