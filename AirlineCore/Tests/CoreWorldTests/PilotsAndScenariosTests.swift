import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct PilotsAndScenariosTests {
    @Test func aSickPilotGroundsTheAircraftUntilTheyAreBack() throws {
        var w = try Fixtures.flyingWorld()
        w.ops.pilots[0].sickUntilMinute = w.clock.minute + 2 * 1440
        w.advance(byMinutes: 1440)
        #expect(w.airline.stats.flights == 0, "nobody rated to fly it")
        #expect(w.news.contains { $0.kind == .noCrew })
        w.advance(byMinutes: 3 * 1440)
        #expect(w.airline.stats.flights > 0, "flying again once the pilot is back")
    }

    @Test func aSparePilotStepsIn() throws {
        var w = try Fixtures.flyingWorld()
        var spare = w.makePilot(group: .singles)
        spare.aircraftID = nil
        w.ops.pilots.append(spare)
        w.ops.pilots[0].sickUntilMinute = w.clock.minute + 5 * 1440
        w.advance(byMinutes: 2 * 1440)
        #expect(w.airline.stats.flights > 0)
        #expect(w.ops.pilots.contains { $0.id == spare.id && $0.aircraftID == w.aircraft[0].id }, "the spare joined the crew")
    }

    @Test func hiringAndTraining() throws {
        var w = try Fixtures.world()
        let candidate = w.ops.pilotMarket[0]
        let cash = w.airline.cash
        try w.hirePilot(id: candidate.id)
        #expect(w.ops.pilots.count == 2 && w.airline.cash == cash - candidate.hireFee)
        let target: RatingGroup = candidate.isRated(.twinProps) ? .pistonTwins : .twinProps
        try w.train(pilotID: candidate.id, for: target)
        #expect(throws: WorldError.alreadyBuilt) { try w.train(pilotID: candidate.id, for: target) }
        w.advance(byMinutes: (World.trainingDays(target) + 8) * 1440)
        let trained = try #require(w.ops.pilots.first { $0.id == candidate.id })
        #expect(trained.isRated(target) && trained.trainingFor == nil)
    }

    @Test func aNewAircraftComesWithItsCrewUnlessHiringIsOff() throws {
        var w = try Fixtures.world()
        w.airline.cash = 30_000_000
        let listing = try #require(w.market.listings.first { (AircraftCatalog.type($0.typeID).map { $0.level <= 1 && w.homeProblem($0) == nil } ?? false) })
        let id = try w.buyUsed(listingID: listing.id)
        Fixtures.advance(&w, days: 12) { $0.aircraft.first { $0.id == id }?.isDelivered == true }
        #expect(w.ops.pilots.contains { $0.aircraftID == id })

        var manual = try Fixtures.world()
        manual.airline.cash = 30_000_000
        manual.setAutoHire(false)
        let other = try #require(manual.market.listings.first { (AircraftCatalog.type($0.typeID).map { $0.level <= 1 && manual.homeProblem($0) == nil } ?? false) })
        let id2 = try manual.buyUsed(listingID: other.id)
        Fixtures.advance(&manual, days: 12) { $0.aircraft.first { $0.id == id2 }?.isDelivered == true }
        #expect(!manual.ops.pilots.contains { $0.aircraftID == id2 })
    }

    @Test func everyScenarioStartsCleanly() throws {
        for def in ScenarioDefinition.all {
            let w = try World.newGame(NewGameConfig(airlineName: "Test Air", airlineCode: "TA", homeAirport: def.home, branding: .starter, difficulty: def.difficulty,
                                                    starterTypeID: def.starterTypeID, seed: 4, scenario: def.id))
            #expect(w.ops.scenario?.id == def.id && w.ops.scenario?.deadlineDay == def.deadlineDays, "\(def.id)")
        }
    }

    @Test func reachingTheGoalEarlyWinsGoldAndMissingTheDeadlineFails() throws {
        guard let def = ScenarioDefinition.definition(.bigCarrier) else { Testing.Issue.record("missing scenario"); return }
        var w = try World.newGame(NewGameConfig(airlineName: "Test Air", airlineCode: "TA", homeAirport: def.home, branding: .starter, difficulty: def.difficulty,
                                                starterTypeID: def.starterTypeID, seed: 4, scenario: def.id))
        w.airline.level = 4
        w.advance(byMinutes: 1440)
        #expect(w.ops.scenario?.medal == .gold && w.ops.scenario?.finishedDay != nil)

        var late = try World.newGame(NewGameConfig(airlineName: "Late Air", airlineCode: "LA", homeAirport: def.home, branding: .starter, difficulty: def.difficulty,
                                                   starterTypeID: def.starterTypeID, seed: 4, scenario: def.id))
        late.ops.scenario?.deadlineDay = 1
        late.advance(byMinutes: 3 * 1440)
        #expect(late.ops.scenario?.failed == true && late.ops.scenario?.medal == nil)
    }

    @Test func freightToTheRightRegionCounts() throws {
        guard let def = ScenarioDefinition.definition(.freezeUp) else { Testing.Issue.record("missing scenario"); return }
        var w = try World.newGame(NewGameConfig(airlineName: "Test Air", airlineCode: "TA", homeAirport: def.home, branding: .starter, difficulty: def.difficulty,
                                                starterTypeID: def.starterTypeID, seed: 4, scenario: def.id))
        w.countScenarioFreight(kg: 5_000, at: "YFB")
        w.countScenarioFreight(kg: 5_000, at: "YEV")
        #expect(w.ops.scenario?.freightKg == 5_000, "only Nunavut counts")
    }
}
