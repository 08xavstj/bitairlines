import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

/// The added systems: set-up, old saves, modes, perks, fuel, service and daylight.
@Suite struct OperationsTests {
    @Test func aNewGameStartsWithACrewRivalsAndAPilotMarket() throws {
        let w = try Fixtures.world()
        #expect(w.ops.mode == .normal)
        #expect(w.ops.pilots.count == 1 && w.ops.pilots[0].aircraftID == w.aircraft[0].id)
        #expect(w.ops.rivals.count >= 3)
        #expect(!w.ops.rivals.contains { $0.routes.contains { $0.a == "YEV" || $0.b == "YEV" } }, "nobody competes at home on day one")
        #expect(w.ops.pilotMarket.count == 6)
        #expect(!w.ops.jobArea.isEmpty && w.ops.jobArea.contains("YUB"))
    }

    @Test func anOldSaveWithoutTheAddedSystemsLoadsAndCatchesUp() throws {
        var w = try Fixtures.flyingWorld()
        w.operationsStore = nil
        let data = try Fixtures.encode(w)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("operationsStore"), "the old save has no added systems")
        var loaded = try JSONDecoder().decode(World.self, from: data)
        #expect(loaded.ops.pilots.isEmpty)
        loaded.advance(byMinutes: 3 * 1440)
        #expect(loaded.operationsStore != nil)
        #expect(loaded.ops.pilots.count == 1, "the fleet got its crew")
        #expect(loaded.airline.stats.flights > 0, "and keeps flying")
    }

    @Test func easyModeIgnoresRunwaysAndSandboxNeverRunsOut() throws {
        let normal = try Fixtures.world()
        let easy = try Fixtures.world(mode: .easy)
        let jet = try Fixtures.type("b738")
        let yev = try Fixtures.airport("YEV")
        #expect(!normal.canUse(type: jet, at: yev))
        #expect(easy.canUse(type: jet, at: yev))

        var sandbox = try Fixtures.world(mode: .sandbox)
        #expect(sandbox.airline.cash == Tuning.sandboxStartCash && sandbox.airline.level == Airline.maxLevel)
        sandbox.airline.cash = -5_000_000
        #expect(sandbox.advance(byMinutes: 20 * 1440) != .gameOver)
        #expect(sandbox.airline.cash > 0 && !sandbox.isBankrupt)
    }

    @Test func realismNeedsFuelStopsAndADepotFixesIt() throws {
        var real = try Fixtures.world(mode: .realism)
        real.airline.cash = 50_000_000
        // Two strips in the same country that sell no fuel, a Caravan's round trip apart (the map keeps few such strips, so look worldwide).
        let dry = AirportCatalog.all.filter { $0.surface != .water && $0.runwayFt >= 1500 && !real.sellsFuel($0) }
        var pair: (Airport, Airport)?
        for a in dry {
            if let b = dry.first(where: { $0.code != a.code && $0.country == a.country && a.distanceKm(to: $0) > 100 && a.distanceKm(to: $0) < 700 }) { pair = (a, b); break }
        }
        let (a, b) = try #require(pair)
        real.airline.permits.append(a.country)
        let id = try real.createRoute(stops: [a.code, b.code])
        let caravan = try Fixtures.type("c208")
        #expect(real.fitProblem(type: caravan, route: try #require(real.routes.first { $0.id == id })) == .noFuel(airport: a.code), "no fuel at either end")
        try real.build(.fuelDepot, at: a.code)
        #expect(real.fitProblem(type: caravan, route: try #require(real.routes.first { $0.id == id })) == nil, "a depot at one end covers the round trip")

        var normal = try Fixtures.world()
        normal.airline.cash = 50_000_000
        normal.airline.permits.append(a.country)
        let id2 = try normal.createRoute(stops: [a.code, b.code])
        #expect(normal.fitProblem(type: caravan, route: try #require(normal.routes.first { $0.id == id2 })) == nil, "Normal mode sells fuel everywhere")
    }

    @Test func eachCertificateUpgradeOffersThreePerks() throws {
        var w = try Fixtures.world()
        w.airline.stats.revenue = 2_000_000
        w.airline.reputation = 20
        try w.upgradeCertificate()
        #expect(w.ops.perkChoices.count == 3)
        let outside = try #require(Perk.allCases.first { !w.ops.perkChoices.contains($0) })
        #expect(throws: WorldError.invalidChoice) { try w.choosePerk(outside) }
        let price = w.permitPrice(country: "US")
        if w.ops.perkChoices.contains(.permitOffice) {
            try w.choosePerk(.permitOffice)
            #expect(w.permitPrice(country: "US") == price / 2)
        } else {
            try w.choosePerk(w.ops.perkChoices[0])
        }
        #expect(w.ops.perks.count == 1 && w.ops.perkChoices.isEmpty)
    }

    @Test func quickTurnsShortenTheTurnaround() throws {
        var w = try Fixtures.world()
        let before = w.turnaroundHours(.turboprop)
        w.ops.perks = [.quickTurns]
        #expect(w.turnaroundHours(.turboprop) < before)
    }

    @Test func fuelBoughtAheadIsUsedByFlightsAndRecorded() throws {
        var w = try Fixtures.flyingWorld()
        let cash = w.airline.cash
        let price = w.fuelPrice(kg: 10_000)
        try w.buyFuel(kg: 10_000)
        #expect(w.airline.cash == cash - price && w.ops.fuel.kg == 10_000)
        #expect(throws: WorldError.fuelStorageFull(capacityKg: Int(w.fuelCapacityKg))) { try w.buyFuel(kg: 50_000) }
        w.advance(byMinutes: 3 * 1440)
        #expect(w.ops.fuel.kg < 10_000, "flights drew on the stock")
        #expect(w.ops.fuelHistory.count >= 3)
    }

    @Test func premiumServiceWinsPeopleAndCostsMore() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        try w.setService(routeID: id, level: .premium)
        let premium = try #require(w.routes.first { $0.id == id })
        try w.setService(routeID: id, level: .basic)
        let basic = try #require(w.routes.first { $0.id == id })
        let caravan = try Fixtures.type("c208")
        let rich = w.forecast(route: premium, type: caravan, aircraftCount: 1)
        let plain = w.forecast(route: basic, type: caravan, aircraftCount: 1)
        #expect(rich.passengersPerDay > plain.passengersPerDay)
        #expect(ServiceLevel.premium.costPerPassenger > ServiceLevel.basic.costPerPassenger)
        #expect(premium.service == .premium && basic.service == .basic)
    }

    @Test func daylightIsShortInTheArcticWinterAndLongInSummer() {
        #expect(World.daylightHours(latitude: 68.3, dayOfYear: 355) == 3)
        #expect(World.daylightHours(latitude: 68.3, dayOfYear: 172) == 24)
        let equator = World.daylightHours(latitude: 0, dayOfYear: 80)
        #expect(equator > 12.5 && equator < 13.5)
    }

    @Test func lakesFreezeInTheNorthernWinter() throws {
        let w = try Fixtures.world()
        let easy = try Fixtures.world(mode: .easy)
        let lake = try #require(AirportCatalog.all.first { $0.surface == .water && $0.latitude > 60 })
        #expect(w.isFrozen(lake, month: 1) && !w.isFrozen(lake, month: 7))
        #expect(!easy.isFrozen(lake, month: 1))
        let floats = try Fixtures.type("dhc6f")
        #expect(!w.canUse(type: floats, at: lake, month: 1) && w.canUse(type: floats, at: lake, month: 7))
        let caravan = try Fixtures.type("c208")
        #expect(w.canUse(type: caravan, kits: [.wheelSkis], at: lake, month: 1), "skis land on the ice")
    }
}
