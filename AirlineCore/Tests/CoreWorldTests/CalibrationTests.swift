import Testing
import CoreCatalog
@testable import CoreWorld

/// Prints what a year of flying earns in a few starter set-ups, so the early game can be tuned by looking at real numbers.
/// The checks are loose on purpose: they guard the shape (right plane for the route wins), not exact dollars.
@Suite struct CalibrationTests {
    struct Result { var profit: Int; var flights: Int; var passengers: Int; var cargoKg: Int }

    func year(type: String, stops: [String], frequency: Double, difficulty: Difficulty = .easy, extraAircraft: Int = 0) throws -> Result {
        var w = try Fixtures.world(seed: 31, type: type, difficulty: difficulty)
        let route = try w.createRoute(stops: stops)
        try w.setFrequency(routeID: route, perDay: frequency)
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        let start = w.airline.cash
        w.advance(byMinutes: 365 * 1440)
        return Result(profit: w.airline.cash - start, flights: w.airline.stats.flights, passengers: w.airline.stats.passengers, cargoKg: w.airline.stats.cargoKg)
    }

    func report(_ name: String, _ r: Result) {
        print("CALIBRATION \(name): profit \(r.profit), flights \(r.flights), pax \(r.passengers), cargo \(r.cargoKg) kg")
    }

    @Test func rightPlaneForTheRoute() throws {
        let caravanThin = try year(type: "c208", stops: ["YEV", "YUB"], frequency: 1)
        let twinThin = try year(type: "dhc6", stops: ["YEV", "YUB"], frequency: 1)
        let caravanFar = try year(type: "c208", stops: ["YEV", "YZF"], frequency: 1)
        let twinFar = try year(type: "dhc6", stops: ["YEV", "YZF"], frequency: 1)
        let twinFarBusy = try year(type: "dhc6", stops: ["YEV", "YZF"], frequency: 2)
        let dcFar = try year(type: "dc3", stops: ["YEV", "YZF"], frequency: 1)
        let milkRun = try year(type: "c208", stops: ["YEV", "YUB", "YSY"], frequency: 1)
        report("caravan YEV-YUB 1/day", caravanThin)
        report("twin otter YEV-YUB 1/day", twinThin)
        report("caravan YEV-YZF 1/day", caravanFar)
        report("twin otter YEV-YZF 1/day", twinFar)
        report("twin otter YEV-YZF 2/day", twinFarBusy)
        report("dc-3 YEV-YZF 1/day", dcFar)
        report("caravan milk run YEV-YUB-YSY 1/day", milkRun)
        #expect(caravanThin.profit > twinThin.profit, "a small plane beats a big one on a thin route")
        #expect(twinFar.profit > caravanFar.profit, "a bigger plane beats a small one on a busy route")
        #expect(caravanThin.profit > 150_000 && caravanThin.profit < 1_500_000)
        #expect(twinFar.profit > 150_000 && twinFar.profit < 3_000_000)
    }
}
