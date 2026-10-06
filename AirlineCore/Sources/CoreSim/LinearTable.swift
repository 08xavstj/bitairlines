// CoreSim/LinearTable.swift: a curve given by points and read by linear interpolation. Portable: no pow, exp or log.
public struct LinearTable: Sendable {
    private let xs: [Double]
    private let ys: [Double]

    /// Points must be sorted by x, ascending.
    public init(_ points: [(Double, Double)]) {
        xs = points.map { $0.0 }
        ys = points.map { $0.1 }
    }

    /// The curve's value at x; below the first point or above the last it holds the end value.
    public func value(at x: Double) -> Double {
        guard let first = xs.first, let last = xs.last else { return 0 }
        if x <= first { return ys[0] }
        if x >= last { return ys[ys.count - 1] }
        var i = 1
        while xs[i] < x { i += 1 }
        let x0 = xs[i - 1], x1 = xs[i], y0 = ys[i - 1], y1 = ys[i]
        return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    }
}
