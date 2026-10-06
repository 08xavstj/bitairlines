import Testing
import CoreCatalog
@testable import CoreWorld

/// A bought barn find is a project: it cannot fly, take a job or keep a route until it is restored, and it comes out of the
/// hangar near new in the heritage livery.
@Suite struct RestorationTests {
    @Test func aBarnFindCannotFlyUntilRestoredAndGetsTheHeritageLiveryAfter() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        w.airline.cash = 100_000_000
        let listingFound = w.addRareFind(.barnFind)
        let listingID = try #require(listingFound)
        let planeID = try w.buyUsed(listingID: listingID)
        let indexFound = w.aircraftIndex(planeID)
        let i = try #require(indexFound)
        #expect(w.aircraft[i].awaitingRestoration)
        #expect(w.aircraft[i].livery == nil)
        #expect(w.restorationProblem(aircraftID: planeID) == .notDelivered)

        // Delivered, it is still a project: no job, and a route does not get it into the air.
        w.advance(byMinutes: GameClock.minutesPerDay)
        #expect(w.aircraft[i].isDelivered && w.aircraft[i].awaitingRestoration)
        w.ops.jobs.append(Job(id: 900, kind: .crewChange, from: "YEV", to: "YUB", passengers: 1, cargoKg: 0, pay: 5_000,
                              deadlineMinute: w.clock.minute + 2 * 1440, expiresMinute: w.clock.minute + 1440, aircraftID: nil, loaded: false))
        #expect(w.jobProblem(jobID: 900, aircraftID: planeID) == .aircraftBusy)
        let routeID = try w.createRoute(stops: ["YEV", "YUB"])
        let routeFound = w.routeIndex(routeID)
        let r = try #require(routeFound)
        let typeFound = w.aircraft[i].type
        let type = try #require(typeFound)
        if w.fitProblem(type: type, route: w.routes[r]) == nil {
            try w.assign(aircraftID: planeID, toRoute: routeID)
            w.advance(byMinutes: 600)
            #expect(w.aircraft[i].routeID == nil, "it leaves the route instead of flying it")
            #expect(w.aircraft[i].totalFlights == 0 && w.aircraft[i].flight == nil)
        }
        #expect(w.saleValue(of: w.aircraft[i]) <= w.aircraft[i].purchasePrice, "no profit from selling it on")

        // The restoration: paid now, weeks in the hangar.
        let costFound = w.restorationCost(aircraftID: planeID)
        let cost = try #require(costFound)
        let daysFound = w.restorationDays(aircraftID: planeID)
        let days = try #require(daysFound)
        #expect(cost > 0)
        #expect(days >= Tuning.restorationBaseDays / 2 && days <= Tuning.restorationMaxDays)
        let cash = w.airline.cash
        let paid = w.aircraft[i].purchasePrice
        try w.startRestoration(aircraftID: planeID)
        #expect(w.airline.cash == cash - cost)
        #expect(w.aircraft[i].purchasePrice == paid + cost, "what was paid counts towards a later sale")
        #expect(!w.aircraft[i].awaitingRestoration)
        if case .maintenance = w.aircraft[i].status {} else { Testing.Issue.record("the restoration takes it into the hangar") }

        Fixtures.advance(&w, days: days + 2) { world in
            if case .maintenance = world.aircraft[i].status { return false }
            return true
        }
        let restored = w.aircraft[i]
        if case .idle = restored.status {} else { Testing.Issue.record("out of the hangar and parked") }
        #expect(restored.condition >= Tuning.conditionAfterCheck)
        #expect(restored.livery?.name == RareFinds.heritageLiveryCode)
        let due = w.isHeavyCheckDue(restored)
        #expect(!due, "the restoration included a heavy check")
    }

    @Test func aRestorationNeedsTheMoney() throws {
        var w = try Fixtures.world()
        w.setPausePolicy(.never)
        w.airline.cash = 100_000_000
        let listingFound = w.addRareFind(.barnFind)
        let listingID = try #require(listingFound)
        let planeID = try w.buyUsed(listingID: listingID)
        w.advance(byMinutes: GameClock.minutesPerDay)
        w.airline.cash = 10
        let costFound = w.restorationCost(aircraftID: planeID)
        let cost = try #require(costFound)
        #expect(w.restorationProblem(aircraftID: planeID) == .notEnoughCash(needed: cost))
        var refused: WorldError?
        do {
            try w.startRestoration(aircraftID: planeID)
        } catch let error as WorldError {
            refused = error
        }
        #expect(refused == .notEnoughCash(needed: cost))
        #expect(w.airline.cash == 10)
    }

    @Test func anOrdinaryAircraftHasNothingToRestore() throws {
        let w = try Fixtures.world()
        let plane = w.aircraft[0]
        #expect(!plane.awaitingRestoration)
        #expect(w.restorationCost(aircraftID: plane.id) == nil)
        #expect(w.restorationProblem(aircraftID: plane.id) == .invalidChoice)
    }
}
