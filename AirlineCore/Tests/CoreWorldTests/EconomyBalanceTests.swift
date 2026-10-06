import Testing
import CoreCatalog
@testable import CoreWorld

/// Lifeline demand for poor fly-in regions, honest forecasts (the real aircraft's wear and its heavy checks) and schedules sized
/// on the share of a contested market the airline can win. The numbers come from tools/sim/start_homes_proto.py.
@Suite struct EconomyBalanceTests {
    /// The starter whose best suggested route earns the most, as a player would pick it (the same rule as PlaythroughTests).
    func bestStart(home: String) throws -> (world: World, idea: RouteIdea)? {
        var best: (world: World, idea: RouteIdea)?
        for offer in World.starterOffers(home: home, difficulty: .standard) {
            let config = NewGameConfig(airlineName: "Bot Air", airlineCode: "BT", homeAirport: home, branding: .starter,
                                       difficulty: .standard, starterTypeID: offer.typeID, seed: 3, mode: .normal)
            guard let w = try? World.newGame(config), let idea = w.routeIdeas(limit: 1).first else { continue }
            if best == nil || idea.profitPerDay > best!.idea.profitPerDay { best = (w, idea) }
        }
        return best
    }

    @Test func poorFlyInTownsTravelAtLeastALifeline() throws {
        let vli = try Fixtures.airport("VLI"), son = try Fixtures.airport("SON")
        let hgu = try Fixtures.airport("HGU"), tbg = try Fixtures.airport("TBG")
        // Port Vila (38,000 people) has no road to Luganville: in a poor country a town that size still counts as fly-in.
        #expect(Demand.isolation(vli) > 0.25)
        let island = Demand.passengersPerDay(from: vli, to: son)
        let highlands = Demand.passengersPerDay(from: hgu, to: tbg)
        print("CALIBRATION lifeline: VLI-SON \(island) a day, HGU-TBG \(highlands) a day")
        #expect(island > 6 && island < 20, "was about 2 a day")
        #expect(highlands > 10 && highlands < 30, "was about 2.4 a day")
        // Rich countries do not move: the fitted anchors stay where the prototype put them (see EconomyPortTests).
        let yev = try Fixtures.airport("YEV"), yub = try Fixtures.airport("YUB")
        #expect(abs(Demand.passengersPerDay(from: yev, to: yub) - 7.558832) < 0.002)
    }

    @Test func everyStartHomeHasAFirstRouteThatPays() throws {
        // Jomsom has 286 people: no rule makes a route from it pay, so it needs a different home in StartRegions (Simikot works).
        let tooSmall: Set<String> = ["JMO"]
        var weakest = Double.greatestFiniteMagnitude, strongest = 0.0
        for region in StartRegions.all {
            for home in region.headquarters {
                let start = try bestStart(home: home)
                let profit = start?.idea.profitPerDay ?? 0
                print("PLAYTEST first route \(region.id) \(home): " + (start.map { "\($0.idea.stops.joined(separator: "-")) \($0.idea.typeID) \(Int($0.idea.profitPerDay))/day" } ?? "none"))
                strongest = max(strongest, profit)
                if tooSmall.contains(home) { continue }
                weakest = min(weakest, profit)
                // Well above head office ($120 a day at level 1); the Outback and Patagonia homes are the lowest at about $940 to $1,450.
                #expect(profit > 900, "\(home): \(Int(profit)) a day")
            }
        }
        print("PLAYTEST first routes: weakest \(Int(weakest)), strongest \(Int(strongest)) a day")
        // The strong polar starts are not made stronger (the best is Cambridge Bay at about $6,000 a day).
        #expect(strongest < 7_000)
    }

    @Test func theForecastUsesTheStartersOwnWear() throws {
        var w = try Fixtures.world(type: "dc3")
        let dc3 = try Fixtures.type("dc3")
        let old = w.forecast(stops: ["YEV", "YCO"], type: dc3, frequency: 1, aircraftCount: 1)
        w.aircraft[0].builtDay = w.clock.dayIndex
        w.aircraft[0].condition = 100
        let young = w.forecast(stops: ["YEV", "YCO"], type: dc3, frequency: 1, aircraftCount: 1)
        print("CALIBRATION forecast DC-3 YEV-YCO: 45-year-old starter \(Int(old.profitPerDay)) a day, new one \(Int(young.profitPerDay)) a day")
        #expect(young.profitPerDay > old.profitPerDay + 500, "a 45-year-old DC-3 costs far more to maintain")
        #expect(old.heavyCheckPerDay > 0 && young.heavyCheckPerDay > 0)
        #expect(old.heavyCheckPerDay > young.heavyCheckPerDay, "an older aircraft's heavy check costs more")
    }

    @Test func aTypeTheAirlineDoesNotHaveIsJudgedAsAnOldTimerFromTheHangar() throws {
        let w = try Fixtures.world()
        let dc3 = try Fixtures.type("dc3")
        let f = w.forecast(stops: ["YEV", "YCO"], type: dc3, frequency: 1, aircraftCount: 1)
        // Priced and maintained as the hangar sells them: about 50 years old, condition 50.
        let expected = Valuation.value(type: dc3, ageYears: Tuning.forecastAgeOutOfProduction, condition: Tuning.forecastConditionOutOfProduction)
        #expect(f.investment == expected)
        let check = Double(w.heavyCheckCost(type: dc3, ageYears: Tuning.forecastAgeOutOfProduction))
        #expect(f.heavyCheckPerDay >= check / Double(Tuning.heavyCheckIntervalDays) - 0.01)
    }

    @Test func aWidebodyScheduleFitsTheShareOfABigMarketItCanWin() throws {
        var w = try Fixtures.world(mode: .sandbox)
        try w.buyPermit(country: "GB")
        try w.buyPermit(country: "US")
        let b789 = try Fixtures.type("b789")
        let plan = w.forecast(stops: ["LHR", "JFK"], type: b789)
        print("CALIBRATION LHR-JFK 787-9: \(plan.frequency) a day with \(plan.aircraftNeeded), load \(plan.loadFactor), \(Int(plan.profitPerDay)) a day")
        // It used to plan for 75% of the whole market (16 a day, half empty, a loss); a newcomer wins at most half of it.
        #expect(plan.problem == nil)
        #expect(plan.frequency <= 8)
        #expect(plan.isViable, "\(plan.profitPerDay)")
        // A remote market has no competition, so its schedule is about what it was.
        let thin = try #require(w.ideaRoute(stops: ["YEV", "YUB"]))
        let caravan = try Fixtures.type("c208")
        let whole = (thin.legs.map { $0.marketPaxPerDay * 0.75 }.min() ?? 0) / (Double(caravan.seats) * 0.8)
        let sized = w.demandFrequency(route: thin, type: caravan)
        #expect(sized <= whole && sized > whole * 0.9)
    }
}
