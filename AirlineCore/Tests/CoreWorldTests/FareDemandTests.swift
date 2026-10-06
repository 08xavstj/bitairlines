import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct FareDemandTests {
    /// Fares 0.50, 0.55, ... 2.00, built from whole numbers so 1.0 is exact.
    let fares: [Double] = (10...40).map { Double($0) / 20.0 }

    @Test func theGoingFareChangesNothing() {
        #expect(FareDemand.factor(ratio: 1.0) == 1.0)
    }

    @Test func cheaperWinsPeopleSlowlyAndDearerLosesThemFaster() {
        #expect(FareDemand.factor(ratio: 1.25) > 1.0 && FareDemand.factor(ratio: 1.25) < 1.2)
        #expect(FareDemand.factor(ratio: 0.8) < 0.75)
        #expect(FareDemand.factor(ratio: 2.0) <= 1.5)
    }

    @Test func revenueOnARouteWithSpareSeatsPeaksNearTheGoingFare() {
        let best = fares.max { a, b in a * FareDemand.factor(ratio: 1.0 / a) < b * FareDemand.factor(ratio: 1.0 / b) } ?? 0
        #expect(best >= 1.0 && best <= 1.2, "best fare \(best)")
    }

    @Test func theForecastPeaksNearTheGoingFareNotAtTheBottom() throws {
        // A Caravan twice a day on Inuvik - Tuktoyaktuk has spare seats even at the lowest fare. Passengers only, so freight does not blur it.
        let w = try Fixtures.world()
        let caravan = try Fixtures.type("c208")
        var bestFare = 0.0, bestProfit = -1.0e12
        for fare in fares {
            let f = w.forecast(stops: ["YEV", "YUB"], type: caravan, frequency: 2, fareMultiplier: fare, carriesCargo: false, aircraftCount: 1)
            if f.profitPerDay > bestProfit { bestProfit = f.profitPerDay; bestFare = fare }
        }
        let low = w.forecast(stops: ["YEV", "YUB"], type: caravan, frequency: 2, fareMultiplier: 0.5, carriesCargo: false, aircraftCount: 1)
        print("CALIBRATION fare sweep Caravan YEV-YUB 2/day: best fare \(bestFare), \(Int(bestProfit)) a day, load at 0.5 \(low.loadFactor)")
        #expect(low.loadFactor < Tuning.loadFactorCap, "the route must have spare seats for this test")
        #expect(bestFare >= 1.0 && bestFare <= 1.2, "best fare \(bestFare)")
    }

    @Test func theRevenueManagerRaisesACheapFareTowardsTheGoingFare() throws {
        var w = try Fixtures.flyingWorld()
        w.pausePolicy = .never
        w.advance(byMinutes: 8 * 1440)
        let load = w.routes[0].seatLoadLast7Days
        try #require(load != nil)
        try w.setFare(routeID: w.routes[0].id, multiplier: 0.7)
        try w.hire(.revenueManager)
        w.manageFares()
        let after = w.routes[0].fareMultiplier
        #expect(after > 0.7)
    }
}
