import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct NewGameTests {
    @Test func startsWithOneUsedAircraftAndWorkingCapital() throws {
        let w = try Fixtures.world()
        #expect(w.aircraft.count == 1)
        #expect(w.aircraft[0].typeID == "c208")
        #expect(w.aircraft[0].location == "YEV")
        #expect(w.aircraft[0].status == .idle)
        #expect(w.airline.cash >= World.workingCapitalFloor)
        #expect(w.airline.cash < Difficulty.standard.startingBudget)
        #expect(w.airline.level == 1)
        #expect(w.airline.permits == ["CA"])
        #expect(w.market.listings.count == 22)
        #expect(w.clock.hour == 6)
        #expect(w.clock.date == CalendarDate(year: 2027, month: 1, day: 1))
    }

    @Test func refusesAStarterThatIsTooBig() {
        #expect(throws: WorldError.levelTooLow(required: 5)) { _ = try Fixtures.world(type: "b738") }
    }

    @Test func refusesAStarterThatCannotUseTheHome() {
        #expect(throws: WorldError.aircraftCannotUse(airport: "YEV")) { _ = try Fixtures.world(type: "c208f") }
    }

    @Test func refusesAnUnknownHome() {
        #expect(throws: WorldError.unknownAirport("ZZZ")) { _ = try Fixtures.world(home: "ZZZ") }
    }

    @Test func starterOffersFitTheBudget() {
        let offers = World.starterOffers(home: "YEV", difficulty: .hard)
        #expect(!offers.isEmpty)
        for o in offers { #expect(o.price <= Difficulty.hard.startingBudget - World.workingCapitalFloor) }
        #expect(offers.contains { $0.typeID == "dc3" })
        #expect(!offers.contains { $0.typeID == "dhc6f" })
    }

    @Test func everyStartRegionHasUsableHeadquarters() {
        for region in StartRegions.all {
            #expect(!region.headquarters.isEmpty, "\(region.id)")
            for code in region.headquarters {
                let airport = AirportCatalog.airport(code)
                #expect(airport != nil, "\(region.id): \(code) is not in the catalog")
                #expect(!World.starterOffers(home: code, difficulty: .standard).isEmpty, "\(region.id): nothing can start at \(code)")
            }
        }
    }

    @Test func buyingAndSellingAnAircraft() throws {
        var w = try Fixtures.world(difficulty: .easy)
        let listing = try #require(w.market.listings.first { (AircraftCatalog.type($0.typeID)?.level ?? 9) <= 1 && $0.price < w.airline.cash })
        let cash = w.airline.cash
        let id = try w.buyUsed(listingID: listing.id)
        #expect(w.airline.cash == cash - listing.price)
        #expect(!w.market.listings.contains { $0.id == listing.id })
        #expect(w.aircraft.first { $0.id == id }?.isDelivered == false)
        #expect(throws: WorldError.notDelivered) { try w.sell(aircraftID: id) }

        w.advance(byMinutes: 12 * 1440)
        #expect(w.aircraft.first { $0.id == id }?.status == .idle)
        let price = try w.sell(aircraftID: id)
        #expect(price < listing.price && price > listing.price / 2)
        #expect(w.aircraft.first { $0.id == id } == nil)
    }

    @Test func cannotBuyWhatYouCannotAffordOrFly() throws {
        var w = try Fixtures.world()
        let big = try #require(w.market.listings.first { (AircraftCatalog.type($0.typeID)?.level ?? 0) >= 2 })
        #expect(throws: WorldError.levelTooLow(required: AircraftCatalog.type(big.typeID)?.level ?? 0)) { try w.buyUsed(listingID: big.id) }
        w.airline.cash = 1000
        let cheap = try #require(w.market.listings.first { (AircraftCatalog.type($0.typeID)?.level ?? 9) <= 1 })
        #expect(throws: WorldError.notEnoughCash(needed: cheap.price)) { try w.buyUsed(listingID: cheap.id) }
        #expect(throws: WorldError.notInProduction) { try w.orderNew(typeID: "dc3") }
    }

    @Test func registrationsAreUniqueAndInTheHomeStyle() throws {
        var w = try Fixtures.world(difficulty: .easy)
        for _ in 0..<5 {
            if let listing = w.market.listings.first(where: { (AircraftCatalog.type($0.typeID)?.level ?? 9) <= 1 && $0.price < w.airline.cash }) { try w.buyUsed(listingID: listing.id) }
        }
        let regs = w.aircraft.map(\.registration)
        #expect(Set(regs).count == regs.count)
        for r in regs { #expect(r.hasPrefix("C-F") && r.count == 6, "\(r)") }
    }

    @Test func marketHasRealisticPrices() throws {
        let w = try Fixtures.world()
        for l in w.market.listings {
            let t = try #require(AircraftCatalog.type(l.typeID))
            #expect(l.price > 0 && l.price <= Int(Double(t.priceUSD) * 1.12), "\(l.typeID) \(l.price)")
            #expect(l.condition >= 30 && l.condition <= 95)
        }
    }
}
