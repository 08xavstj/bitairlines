import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

/// Rivals that fight back (fare wars, more flights, pulling out), growth by level, hubs that count each pair once, old rival saves.
@Suite struct RivalsTests2 {
    @Test func aRivalOnABusyProfitablePairCutsFaresOrAddsFlights() throws {
        var w = try Fixtures.world()
        w.airline.level = 2
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        let r = try #require(w.routeIndex(id))
        w.routes[r].revenueLastMonth = 200_000
        w.routes[r].costLastMonth = 50_000
        w.ops.rivals[0].routes.append(RivalRoute(a: "YUB", b: "YEV", frequency: 2, fareLevel: 1.0, startedDay: 0))
        for _ in 0..<60 { w.weeklyRivals() }
        let theirs = try #require(w.ops.rivals[0].routes.first { $0.serves("YEV", "YUB") })
        let answered = theirs.isCuttingFares || theirs.addedFlights > 0
        #expect(answered, "the rival fights back on the player's best route")
        let news = w.news.filter { $0.kind == .rivalRoute && ($0.subject.hasPrefix("cut:") || $0.subject.hasPrefix("more:")) }
        #expect(!news.isEmpty)
        let moved = theirs.lastMoveDay
        #expect(moved != nil)
    }

    @Test func noAnswerAtLevelOne() throws {
        var w = try Fixtures.world()
        w.airline.level = 1
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        let r = try #require(w.routeIndex(id))
        w.routes[r].revenueLastMonth = 200_000
        w.routes[r].costLastMonth = 50_000
        w.ops.rivals[0].routes.append(RivalRoute(a: "YUB", b: "YEV", frequency: 2, fareLevel: 1.0, startedDay: 0))
        for _ in 0..<20 { w.weeklyRivals() }
        let theirs = try #require(w.ops.rivals[0].routes.first { $0.serves("YEV", "YUB") })
        #expect(theirs.fareLevel == 1.0 && theirs.addedFlights == 0)
    }

    @Test func addedRivalFlightsMakeTheMarketHarder() throws {
        let w = try Fixtures.world()
        var theirs = RivalRoute(a: "YUB", b: "YEV", frequency: 2, fareLevel: 1.0, startedDay: 0)
        let before = w.rivalPressure([theirs])
        theirs.addedFlights = 2
        let after = w.rivalPressure([theirs])
        #expect(before == Tuning.rivalIntensity)
        #expect(after > before && after <= Tuning.rivalIntensityMax)
    }

    @Test func aBeatenRivalLeaves() throws {
        var w = try Fixtures.world()
        w.airline.level = 1
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        try w.setFrequency(routeID: id, perDay: 4)
        try w.setFare(routeID: id, multiplier: 0.8)
        w.ops.rivals[0].routes.append(RivalRoute(a: "YEV", b: "YUB", frequency: 1, fareLevel: 1.0, startedDay: 0))
        let expected = "left:" + w.ops.rivals[0].code + ":YEV:YUB"
        for _ in 0..<(Tuning.rivalLeaveWeeks - 1) { w.weeklyRivals() }
        let stillThere = w.rivalRoutes("YEV", "YUB")
        #expect(stillThere.count == 1)
        #expect(stillThere.first?.weeksLosing == Tuning.rivalLeaveWeeks - 1)
        w.weeklyRivals()
        let gone = w.rivalRoutes("YEV", "YUB")
        #expect(gone.isEmpty)
        let news = w.news.filter { $0.kind == .rivalRoute && $0.subject == expected }
        #expect(news.count == 1)
    }

    @Test func aRivalThatHoldsItsOwnStays() throws {
        var w = try Fixtures.world()
        w.airline.level = 1
        let id = try w.createRoute(stops: ["YEV", "YUB"])
        try w.setFrequency(routeID: id, perDay: 1)
        w.ops.rivals[0].routes.append(RivalRoute(a: "YEV", b: "YUB", frequency: 2, fareLevel: 1.0, startedDay: 0))
        for _ in 0..<(Tuning.rivalLeaveWeeks + 2) { w.weeklyRivals() }
        let theirs = w.rivalRoutes("YEV", "YUB")
        #expect(theirs.count == 1)
    }

    @Test func remoteFlyInMarketsStayRivalFree() throws {
        let w = try Fixtures.world()
        #expect(w.isRemoteMarket("YEV", "YUB"))
        #expect(!w.isRemoteMarket("YYZ", "YUL"))
    }

    @Test func rivalsGrowAtHigherLevels() throws {
        var w = try Fixtures.world()
        w.airline.level = 7
        let before = w.ops.rivals.reduce(0) { $0 + $1.routes.count }
        for _ in 0..<24 { w.growRivals(first: 0) }
        let after = w.ops.rivals.reduce(0) { $0 + $1.routes.count }
        #expect(after > before)
        let cap = Tuning.rivalRoutesBase + Tuning.rivalRoutesPerLevel * 7
        let tooBig = w.ops.rivals.filter { $0.routes.count > cap }
        #expect(tooBig.isEmpty)
    }

    @Test func hubDemandForAPairIsCountedOnce() throws {
        var one = try Fixtures.world()
        one.airline.level = 2
        one.airline.cash = 20_000_000
        _ = try one.createRoute(stops: ["YUB", "YEV"])
        _ = try one.createRoute(stops: ["YEV", "YZF"])
        try one.build(.hubTerminal, at: "YEV")
        var two = one
        _ = try two.createRoute(stops: ["YUB", "YEV"])
        one.refreshConnections()
        two.refreshConnections()
        let paxOne = RivalsTests2.throughPax(one), paxTwo = RivalsTests2.throughPax(two)
        let moneyOne = RivalsTests2.throughRevenue(one), moneyTwo = RivalsTests2.throughRevenue(two)
        #expect(paxOne > 0)
        #expect(abs(paxOne - paxTwo) < 1e-6 * paxOne, "a second feeder route splits the same people, it does not add more")
        #expect(abs(moneyOne - moneyTwo) < 1e-6 * moneyOne)
    }

    @Test func oldRivalSavesDecode() throws {
        let json = #"{"id":1,"name":"Tamarack Air","code":"TK","primary":9,"secondary":2,"home":"YZF","routes":[{"a":"YZF","b":"YEG","frequency":2,"fareLevel":1,"startedDay":0}]}"#
        let rival = try JSONDecoder().decode(Rival.self, from: Data(json.utf8))
        let route = try #require(rival.routes.first)
        #expect(route.addedFlights == 0 && route.weeksLosing == 0 && route.lastMoveDay == nil && !route.isCuttingFares)

        var changed = rival
        changed.routes[0].addedFlights = 1
        changed.routes[0].weeksLosing = 3
        changed.routes[0].lastMoveDay = 40
        let data = try JSONEncoder().encode(changed)
        let back = try JSONDecoder().decode(Rival.self, from: data)
        #expect(back == changed)
    }

    static func throughPax(_ w: World) -> Double {
        w.routes.reduce(0.0) { sum, route in sum + route.legs.reduce(0.0) { $0 + $1.connectingPaxPerDay } }
    }

    static func throughRevenue(_ w: World) -> Double {
        w.routes.reduce(0.0) { sum, route in sum + route.legs.reduce(0.0) { $0 + $1.connectingPaxPerDay * $1.connectingFare } }
    }
}
