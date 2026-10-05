// CoreSim/GeoMath.swift: great-circle distance with arithmetic only (no libm), so every device and build agrees to the last bit.
public enum GeoMath {
    public static let earthRadiusKm = 6371.0088
    static let pi = 3.141592653589793
    static let halfPi = 1.5707963267948966
    static let twoPi = 6.283185307179586

    /// Sine of an angle in radians. Range-reduced to [-pi/2, pi/2], then a Taylor series through x^13 (error below 1e-9).
    public static func sin(_ x: Double) -> Double {
        var r = x - twoPi * (x / twoPi).rounded()
        if r > halfPi { r = pi - r } else if r < -halfPi { r = -pi - r }
        let r2 = r * r
        var s = 1.0 / 6_227_020_800.0
        s = r2 * s - 1.0 / 39_916_800.0
        s = r2 * s + 1.0 / 362_880.0
        s = r2 * s - 1.0 / 5_040.0
        s = r2 * s + 1.0 / 120.0
        s = r2 * s - 1.0 / 6.0
        s = r2 * s + 1.0
        return r * s
    }

    public static func cos(_ x: Double) -> Double { sin(x + halfPi) }

    /// Arc sine on [-1, 1]: a polynomial first guess, then Newton steps on `sin`, so it is exact enough and still libm-free.
    public static func asin(_ x: Double) -> Double {
        let c = max(-1.0, min(1.0, x))
        let a = c < 0 ? -c : c
        let guess = halfPi - (1.0 - a).squareRoot() * (1.5707288 - 0.2121144 * a + 0.0742610 * a * a - 0.0187293 * a * a * a)
        var y = c < 0 ? -guess : guess
        for _ in 0..<3 {
            let slope = cos(y)
            if slope < 1e-6 { break }
            y -= (sin(y) - c) / slope
        }
        return y
    }

    /// Great-circle (haversine) distance in kilometres between two points given in degrees.
    public static func distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let rad = pi / 180.0
        let p1 = lat1 * rad, p2 = lat2 * rad
        let sLat = sin((lat2 - lat1) * rad / 2.0)
        let sLon = sin((lon2 - lon1) * rad / 2.0)
        let a = sLat * sLat + cos(p1) * cos(p2) * sLon * sLon
        return earthRadiusKm * 2.0 * asin(a.squareRoot())
    }
}
