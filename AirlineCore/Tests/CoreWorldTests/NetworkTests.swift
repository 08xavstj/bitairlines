import Testing
import CoreCatalog
@testable import CoreWorld

/// Hubs and connecting passengers, slots at busy airports, rival airlines.
@Suite struct NetworkTests {
    @Test func aHubCarriesPeopleBetweenTwoRoutes() throws {
        var w = try Fixtures.world()
        w.airline.level = 2
        w.airline.cash = 20_000_000
        let feeder = try w.createRoute(stops: ["YUB", "YEV"])
        let trunk = try w.createRoute(stops: ["YEV", "YZF"])
        w.refreshConnections()
        #expect(w.routes.allSatisfy { $0.legs.allSatisfy { $0.connectingPaxPerDay == 0 } }, "no hub, no connections")
        try w.build(.hubTerminal, at: "YEV")
        w.refreshConnections()
        let inbound = try #require(w.routes.first { $0.id == feeder }?.legs.first { $0.from == "YUB" })
        let outbound = try #require(w.routes.first { $0.id == trunk }?.legs.first { $0.from == "YEV" })
        #expect(inbound.connectingPaxPerDay > 0 && outbound.connectingPaxPerDay > 0)
        #expect(inbound.connectingFare > 0 && inbound.connectingFare < outbound.connectingFare, "the short leg gets the smaller share of the fare")
        #expect(inbound.blendedFare != inbound.marketFare)
    }

    @Test func busyAirportsNeedSlotsAndSmallOnesDoNot() throws {
        var w = try Fixtures.world()
        let easy = try Fixtures.world(mode: .easy)
        let busy = try #require(AirportCatalog.all.first { Progression.requiredLevel(for: $0) >= Tuning.slotAirportLevel })
        #expect(w.needsSlots(busy) && !easy.needsSlots(busy))
        #expect(!w.needsSlots(try Fixtures.airport("YEV")))
        w.airline.cash = 50_000_000
        let cash = w.airline.cash
        let price = w.slotPrice(at: busy)
        try w.buySlots(at: busy.code, count: 2)
        #expect(w.slotsHeld(at: busy.code) == 2 && w.airline.cash == cash - 2 * price)
        try w.sellSlots(at: busy.code, count: 1)
        #expect(w.slotsHeld(at: busy.code) == 1 && w.airline.cash == cash - 2 * price + price / 2)
        #expect(throws: WorldError.cannotBuildHere) { try w.buySlots(at: "YEV", count: 1) }
    }

    @Test func aRivalOnTheSamePairTakesShareAndAnswersAFareCut() throws {
        var w = try Fixtures.world()
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        let r = try #require(w.routeIndex(id))
        let yev = try Fixtures.airport("YEV"), yub = try Fixtures.airport("YUB")
        let alone = w.capture(route: w.routes[r], leg: w.routes[r].legs[0], from: yev, to: yub)
        w.ops.rivals[0].routes.append(RivalRoute(a: "YUB", b: "YEV", frequency: 2, fareLevel: 0.9, startedDay: 0))
        let contested = w.capture(route: w.routes[r], leg: w.routes[r].legs[0], from: yev, to: yub)
        #expect(contested < alone)

        try w.setFare(routeID: id, multiplier: 0.7)
        w.monthlyRivals()
        let theirs = try #require(w.ops.rivals[0].routes.first { $0.serves("YEV", "YUB") })
        #expect(theirs.fareLevel < 0.9, "a price war")
    }

    @Test func theRankingsListEveryAirlineBiggestFirst() throws {
        let w = try Fixtures.world()
        let rows = w.rankings
        #expect(rows.count == w.ops.rivals.count + 1)
        #expect(rows.contains { $0.isPlayer && $0.code == "LT" })
        let pax = rows.map(\.passengersPerYear)
        #expect(pax == pax.sorted(by: >))
    }
}
