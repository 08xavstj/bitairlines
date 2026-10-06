import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct JobsAndEventsTests {
    func job(_ w: World, from: String = "YEV", to: String = "YUB", passengers: Int = 4, cargo: Int = 0, pay: Int = 6_000) -> Job {
        Job(id: 900, kind: .crewChange, from: from, to: to, passengers: passengers, cargoKg: cargo, pay: pay,
            deadlineMinute: w.clock.minute + 2 * 1440, expiresMinute: w.clock.minute + 1440, aircraftID: nil, loaded: false)
    }

    @Test func theBoardFillsWithSensibleJobs() throws {
        var w = try Fixtures.world()
        w.advance(byMinutes: 4 * 1440)
        #expect(!w.ops.jobs.isEmpty)
        for j in w.ops.jobs {
            #expect(j.from != j.to && j.pay > 0 && (j.passengers > 0 || j.cargoKg > 0))
            #expect(j.deadlineMinute > j.expiresMinute)
            #expect(w.ops.jobArea.contains(j.from) && w.ops.jobArea.contains(j.to))
        }
        #expect(w.ops.jobs.count <= w.jobBoardSize)
    }

    @Test func aJobIsFlownAndPaidThenTheAircraftGoesBackToItsRoute() throws {
        var w = try Fixtures.flyingWorld()
        let plane = w.aircraft[0].id
        let route = try #require(w.aircraft[0].routeID)
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        #expect(w.aircraft[0].jobID == 900 && w.aircraft[0].routeID == nil && w.aircraft[0].returnRouteID == route)
        let revenue = w.airline.stats.revenue
        Fixtures.advance(&w, days: 5) { $0.ops.jobsDone.count == 1 }
        #expect(w.ops.jobsDone.count == 1 && w.ops.jobsDone[0].onTime)
        #expect(w.airline.stats.revenue >= revenue + 6_000)
        #expect(w.ops.jobs.allSatisfy { $0.id != 900 })
        #expect(w.aircraft[0].jobID == nil && w.aircraft[0].routeID == route, "back on its route")
    }

    @Test func jobsThatDoNotFitAreRefused() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        w.ops.jobs.append(job(w, passengers: 30))
        #expect(w.jobProblem(jobID: 900, aircraftID: plane) == .notEnoughRoom)
        #expect(w.jobProblem(jobID: 12345, aircraftID: plane) == .jobUnavailable)
    }

    @Test func droppingAJobFreesTheAircraft() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        w.ops.jobs.append(job(w))
        try w.takeJob(jobID: 900, aircraftID: plane)
        try w.dropJob(jobID: 900)
        #expect(w.aircraft[0].jobID == nil && w.ops.jobs.isEmpty)
    }

    @Test func anEarlyThawLiftsFreightNearby() throws {
        var w = try Fixtures.world()
        w.startEvent(.earlyThaw, at: "YUB")
        let f = w.eventFactors(from: try Fixtures.airport("YEV"), to: try Fixtures.airport("YUB"))
        #expect(f.cargo == 2.0)
        let far = w.eventFactors(from: try Fixtures.airport("YEV"), to: try Fixtures.airport("YVR"))
        #expect(far.cargo == 1.0)
    }

    @Test func theWinterGamesComeWithAnOfferToSponsor() throws {
        var w = try Fixtures.world()
        w.startEvent(.winterGames, at: "YEV")
        let offer = try #require(w.ops.offers.first)
        let cash = w.airline.cash
        let reputation = w.airline.reputation
        try w.acceptOffer(id: offer.id)
        #expect(w.airline.cash == cash - offer.costUSD && w.airline.reputation > reputation)
        #expect(w.ops.offers.isEmpty)
    }

    @Test func aFireBringsEvacuationJobsAndAnOilShockRaisesFuel() throws {
        var w = try Fixtures.world()
        w.startEvent(.forestFire, at: "YUB")
        #expect(w.ops.jobs.contains { $0.kind == .evacuation && $0.from == "YUB" })
        let fuel = w.market.fuelIndex
        w.startEvent(.oilShock, at: "YEV")
        #expect(w.market.fuelIndex > fuel)
    }
}
