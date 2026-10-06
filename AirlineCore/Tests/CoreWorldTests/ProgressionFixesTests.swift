import Testing
import CoreCatalog
@testable import CoreWorld

/// Fixes from the progression playtest: route ideas count the slots a busy airport needs, aircraft that cannot use the
/// headquarters are delivered to the nearest airport of the network that they can use, and level 7 has a new-build aircraft.
@Suite struct ProgressionFixesTests {
    // MARK: Slots in route ideas

    @Test func aRouteIntoABusyCityCountsTheSlotsItNeeds() throws {
        var w = try Fixtures.world()
        w.airline.level = 4
        let yvr = try Fixtures.airport("YVR")
        #expect(w.needsSlots(yvr))
        let needs = w.slotNeeds(stops: ["YEV", "YVR"], frequency: 3)
        let found = needs.first { $0.airport == "YVR" }
        let atVancouver = try #require(found)
        #expect(atVancouver.slots == 3 && atVancouver.noneHeld)
        #expect(atVancouver.cost == 3 * w.slotPrice(at: yvr))
        let atHome = needs.contains { $0.airport == "YEV" }
        #expect(!atHome, "Inuvik hands out no slots")
        let total = w.slotCost(stops: ["YEV", "YVR"], frequency: 3)
        #expect(total == atVancouver.cost)

        w.airline.cash = 50_000_000
        try w.buySlots(at: "YVR", count: 2)
        let fewer = w.slotNeeds(stops: ["YEV", "YVR"], frequency: 3)
        #expect(fewer.count == 1)
        #expect(fewer.first?.slots == 1 && fewer.first?.noneHeld == false)
        let none = w.slotNeeds(stops: ["YEV", "YVR"], frequency: 2)
        #expect(none.isEmpty, "two departures a day fit the two slots held")
    }

    @Test func biggerCityIdeasCarryTheirSlotBill() throws {
        var w = try Fixtures.world()
        w.airline.level = 4
        let ideas = w.routeIdeas(limit: 8, focus: .biggerCities)
        print("CALIBRATION bigger-city slots YEV level 4: " + ideas.map { "\($0.id) \($0.typeID) \(Int($0.profitPerDay))/day slots \($0.slotsNeeded) \($0.slotCost)" }.joined(separator: "; "))
        #expect(!ideas.isEmpty)
        for idea in ideas {
            for code in idea.stops {
                let airport = try Fixtures.airport(code)
                if w.needsSlots(airport) && w.slotsHeld(at: code) == 0 {
                    let listed = idea.slotNeeds.contains { $0.airport == code && $0.slots >= 1 && $0.noneHeld }
                    #expect(listed, "\(idea.id) needs slots at \(code)")
                }
            }
            let sum = idea.slotNeeds.reduce(0) { $0 + $1.cost }
            #expect(idea.slotCost == sum)
        }
        let values = ideas.map(\.rankValue)
        #expect(values == values.sorted(by: >), "ranked with the slot bill counted")
        let withSlots = ideas.contains { $0.slotsNeeded > 0 }
        #expect(withSlots, "at level 4 most bigger cities hand out slots")
    }

    @Test func bushIdeasNeedNoSlots() throws {
        let w = try Fixtures.world()
        let ideas = w.routeIdeas()
        let anySlots = ideas.contains { !$0.slotNeeds.isEmpty }
        #expect(!anySlots)
        for idea in ideas { #expect(idea.rankValue == idea.profitPerDay, "\(idea.id)") }
    }

    // MARK: Deliveries

    @Test func aFloatplaneIsDeliveredToAWaterBaseOnTheNetwork() throws {
        var w = try Fixtures.world()
        w.airline.cash = 50_000_000
        let floats = try Fixtures.type("c208f")
        #expect(w.deliveryAirport(for: floats) == nil)
        #expect(w.deliveryProblem(floats) == .aircraftCannotUse(airport: "YEV"))

        _ = try w.createRoute(stops: ["YEV", "YWS"])
        #expect(w.homeProblem(floats) == .aircraftCannotUse(airport: "YEV"), "home still cannot take it")
        #expect(w.deliveryAirport(for: floats) == "YWS")
        #expect(w.deliveryProblem(floats) == nil)
        #expect(w.deliveryAirport(for: try Fixtures.type("c208")) == "YEV", "what can land at home still goes home")

        w.market.listings.append(UsedListing(id: 9_998, typeID: "c208f", ageYears: 10, condition: 80, price: 1_000_000, deliveryDays: 3))
        let id = try w.buyUsed(listingID: 9_998)
        let found = w.aircraft.first { $0.id == id }
        let plane = try #require(found)
        #expect(plane.location == "YWS")
    }

    @Test func aWidebodyIsDeliveredToALongRunwayOnTheNetwork() throws {
        var w = try Fixtures.world()
        w.airline.level = 6
        w.airline.cash = 500_000_000
        let dreamliner = try Fixtures.type("b789")
        #expect(w.deliveryProblem(dreamliner) == .aircraftCannotUse(airport: "YEV"))
        #expect(throws: WorldError.aircraftCannotUse(airport: "YEV")) { try w.orderNew(typeID: "b789") }

        _ = try w.createRoute(stops: ["YEV", "YVR"])
        #expect(w.deliveryAirport(for: dreamliner) == "YVR")
        let id = try w.orderNew(typeID: "b789")
        let found = w.aircraft.first { $0.id == id }
        let plane = try #require(found)
        #expect(plane.location == "YVR")
    }

    // MARK: Level 7

    @Test func levelSevenOffersANewBuildAircraft() throws {
        let top = AircraftCatalog.all.filter { $0.level == 7 }
        let newBuild = top.filter(\.inProduction).map(\.id)
        #expect(newBuild == ["b779"], "level 7 has an aircraft new from the factory")

        var w = try Fixtures.world()
        w.airline.level = 7
        w.airline.cash = 1_000_000_000
        _ = try w.createRoute(stops: ["YEV", "YVR"])
        let id = try w.orderNew(typeID: "b779")
        let found = w.aircraft.first { $0.id == id }
        let plane = try #require(found)
        #expect(plane.location == "YVR" && plane.condition == 100)
    }
}
