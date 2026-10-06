import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct ForecastTests {
    func type(_ id: String) throws -> AircraftType { try #require(AircraftCatalog.type(id)) }

    @Test func theForecastTracksARealSimulatedYear() throws {
        // A Caravan on Inuvik - Tuktoyaktuk, one flight a day each way, flown for a year in the simulation.
        var w = try Fixtures.world(seed: 21)
        let predicted = w.forecast(stops: ["YEV", "YUB"], type: try type("c208"), frequency: 1, aircraftCount: 1)
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.setFrequency(routeID: route, perDay: 1)
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        let start = w.airline.cash
        w.advance(byMinutes: 365 * 1440)
        // The forecast leaves out head office costs, so add them back to the simulated profit.
        let simulated = Double(w.airline.cash - start) / 365.0 + Tuning.headOfficePerDay(level: 1)
        // The forecast now also counts heavy checks spread over the days, and this year has none (the starter's first one falls
        // due in its second year), so compare without them.
        let flown = predicted.profitPerDay + predicted.heavyCheckPerDay
        print("CALIBRATION forecast Caravan YEV-YUB: predicted \(Int(predicted.profitPerDay)) a day (\(Int(flown)) before heavy checks), simulated \(Int(simulated)) a day, load \(predicted.loadFactor)")
        #expect(predicted.problem == nil && predicted.aircraftNeeded == 1 && predicted.frequency == 1)
        #expect(predicted.heavyCheckPerDay > 0)
        #expect(flown > simulated * 0.75 && flown < simulated * 1.3, "predicted \(flown) vs simulated \(simulated)")
    }

    @Test func aircraftThatCannotFlyTheRouteSaySo() throws {
        let w = try Fixtures.world()
        let jet = w.forecast(stops: ["YEV", "YUB"], type: try type("b738"))
        #expect(jet.problem == .aircraftCannotUse(airport: "YEV") && !jet.isViable)
        let floats = w.forecast(stops: ["YEV", "YUB"], type: try type("dhc6f"))
        #expect(floats.problem == .aircraftCannotUse(airport: "YEV"))
        let tooFar = w.forecast(stops: ["YEV", "YZF"], type: try type("c172"))
        #expect(tooFar.problem != nil)
    }

    @Test func aBigAircraftOnAThinRouteLosesMoney() throws {
        let w = try Fixtures.world(difficulty: .easy)
        let small = w.forecast(stops: ["YEV", "YUB"], type: try type("c208"))
        let big = w.forecast(stops: ["YEV", "YUB"], type: try type("dc3"), frequency: 1, aircraftCount: 1)
        print("CALIBRATION forecast thin route: Caravan \(Int(small.profitPerDay)) a day, DC-3 \(Int(big.profitPerDay)) a day")
        #expect(small.profitPerDay > big.profitPerDay)
    }

    @Test func aBusyRouteNeedsMoreAircraftAndEarnsMore() throws {
        let w = try Fixtures.world(difficulty: .easy)
        let thin = w.forecast(stops: ["YEV", "YUB"], type: try type("dhc6"))
        let busy = w.forecast(stops: ["YEV", "YZF"], type: try type("dhc6"))
        print("CALIBRATION forecast Twin Otter: thin \(Int(thin.profitPerDay)) a day with \(thin.aircraftNeeded), busy \(Int(busy.profitPerDay)) a day with \(busy.aircraftNeeded), payback \(busy.paybackYears ?? -1) years")
        #expect(busy.aircraftNeeded >= thin.aircraftNeeded)
        #expect(busy.profitPerDay > thin.profitPerDay)
    }

    @Test func rankingListsOnlyAircraftThatPayAndSortsByPayback() throws {
        let w = try Fixtures.world()
        for stops in [["YEV", "YUB"], ["YEV", "YZF"], ["YEV", "YUB", "YSY"]] {
            let ranked = w.rankedForecasts(stops: stops, limit: 6)
            print("CALIBRATION ranking \(stops.joined(separator: ">")): " + ranked.map { "\($0.typeID) \(Int($0.profitPerDay))/day pays back in \(String(format: "%.1f", $0.paybackYears ?? -1)) years with \($0.aircraftNeeded)" }.joined(separator: "; "))
            #expect(!ranked.isEmpty, "\(stops)")
            #expect(ranked.allSatisfy { $0.isViable && $0.paybackYears != nil })
            let paybacks = ranked.compactMap(\.paybackYears)
            #expect(paybacks == paybacks.sorted())
            #expect(!ranked.contains { $0.typeID == "b738" }, "a jet cannot use these strips")
        }
    }

    @Test func aRouteThatExistsForecastsWithItsOwnSchedule() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        try w.setFrequency(routeID: id, perDay: 2)
        try w.setFare(routeID: id, multiplier: 1.5)
        let route = try #require(w.routes.first { $0.id == id })
        let caravan = try type("c208")
        let dear = w.forecast(route: route, type: caravan, aircraftCount: 1)
        var cheapRoute = route
        cheapRoute.fareMultiplier = 0.8
        let cheap = w.forecast(route: cheapRoute, type: caravan, aircraftCount: 1)
        #expect(dear.frequency == 2 && cheap.frequency == 2)
        #expect(dear.passengersPerDay < cheap.passengersPerDay, "a higher fare carries fewer people")
    }

    @Test func cargoCanBeLeftOutOfTheForecast() throws {
        let w = try Fixtures.world()
        let caravan = try type("c208")
        let with = w.forecast(stops: ["YEV", "YUB"], type: caravan, frequency: 1, aircraftCount: 1)
        let without = w.forecast(stops: ["YEV", "YUB"], type: caravan, frequency: 1, carriesCargo: false, aircraftCount: 1)
        #expect(with.cargoKgPerDay > 0 && without.cargoKgPerDay == 0)
        #expect(with.revenuePerDay > without.revenuePerDay)
    }
}
