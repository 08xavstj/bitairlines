import Testing
@testable import CoreSim

@Suite struct GeoMathTests {
    @Test func sineAndCosineMatchKnownValues() {
        #expect(abs(GeoMath.sine(0)) < 1e-12)
        #expect(abs(GeoMath.sine(GeoMath.halfPi) - 1) < 1e-9)
        #expect(abs(GeoMath.sine(GeoMath.pi / 6) - 0.5) < 1e-9)
        #expect(abs(GeoMath.cosine(0) - 1) < 1e-9)
        #expect(abs(GeoMath.sine(-7.0) - (-0.6569865987187891)) < 1e-8)
        #expect(abs(GeoMath.cosine(100.0) - 0.8623188722876839) < 1e-7)
    }

    @Test func arcSineRoundTrips() {
        for x in stride(from: -0.99, through: 0.99, by: 0.11) {
            #expect(abs(GeoMath.sine(GeoMath.arcSine(x)) - x) < 1e-8)
        }
    }

    @Test(arguments: [
        (68.3042, -133.4829, 69.4333, -133.0264, 126.876),      // Inuvik - Tuktoyaktuk
        (68.3042, -133.4829, 62.4627, -114.4403, 1087.973),     // Inuvik - Yellowknife
        (51.4706, -0.4619, 40.6398, -73.7789, 5539.654),        // London - New York
        (-33.9461, 151.1772, 33.9425, -118.4081, 12061.120),    // Sydney - Los Angeles
        (1.3644, 103.9915, 51.4706, -0.4619, 10881.879),        // Singapore - London
        (-37.0082, 174.7850, 25.2731, 51.6081, 14533.576),      // Auckland - Doha
        (35.7647, 140.3864, 21.3187, -157.9224, 6136.146),      // Tokyo - Honolulu (crosses the date line)
    ])
    func distanceMatchesHaversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double, expected: Double) {
        let d = GeoMath.distanceKm(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
        #expect(abs(d - expected) / expected < 0.0005)
    }

    @Test func distanceToSelfIsZeroAndSymmetric() {
        #expect(GeoMath.distanceKm(lat1: 10, lon1: 10, lat2: 10, lon2: 10) == 0)
        let a = GeoMath.distanceKm(lat1: 45, lon1: 7, lat2: -20, lon2: 130)
        let b = GeoMath.distanceKm(lat1: -20, lon1: 130, lat2: 45, lon2: 7)
        #expect(abs(a - b) < 1e-9)
    }

    @Test func veryShortHopsAreStillAccurate() {
        // 0.01 degrees of latitude is about 1.112 km
        let d = GeoMath.distanceKm(lat1: 68.0, lon1: -133.0, lat2: 68.01, lon2: -133.0)
        #expect(abs(d - 1.1119) < 0.002)
    }
}
