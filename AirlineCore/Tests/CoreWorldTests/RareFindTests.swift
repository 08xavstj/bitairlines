import Foundation
import Testing
import CoreCatalog
import CoreSim
@testable import CoreWorld

/// Rare finds on the used market: they come up now and then, are priced by kind, and a heritage find arrives in its paint.
@Suite struct RareFindTests {
    /// Moves the clock a week on and turns the market over, as the weekly update does.
    static func nextWeek(_ w: inout World) {
        w.clock.minute += 7 * GameClock.minutesPerDay
        w.rotateListings()
    }

    @Test func aYearOfMarketsBringsAtLeastOneRareFind() throws {
        var w = try Fixtures.world()
        var seen = 0
        var lastID = 0
        for _ in 0..<52 {
            Self.nextWeek(&w)
            for listing in w.rareListings where listing.id > lastID {
                seen += 1
                lastID = listing.id
            }
        }
        #expect(seen >= 1)
        #expect(w.news.contains { $0.kind == .milestone && $0.subject.hasPrefix("rare:") })
    }

    @Test func rareFindsNeverTouchTheWorldsOwnRandomStream() throws {
        var a = try Fixtures.world()
        var b = a
        b.ops.rng = SeededRandom(seed: 99)
        a.ops.rng = SeededRandom(seed: 1)
        for _ in 0..<52 {
            Self.nextWeek(&a)
            Self.nextWeek(&b)
        }
        #expect(a.rng == b.rng)
        #expect(a.market.listings.filter { $0.rare == nil }.count == b.market.listings.filter { $0.rare == nil }.count)
    }

    @Test func aRareFindStaysTwoWeeksThenLeaves() throws {
        var w = try Fixtures.world()
        let idFound = w.addRareFind(.barnFind)
        let id = try #require(idFound)
        Self.nextWeek(&w)
        #expect(w.market.listings.contains { $0.id == id }, "still there after one turnover")
        Self.nextWeek(&w)
        #expect(!w.market.listings.contains { $0.id == id }, "gone after two weeks")
    }

    @Test func eachKindIsPricedByItsShareOfTheValue() throws {
        var w = try Fixtures.world()
        for kind in RareFind.allCases {
            let idFound = w.addRareFind(kind)
            let id = try #require(idFound)
            let listing = try #require(w.market.listings.first { $0.id == id })
            let type = try Fixtures.type(listing.typeID)
            let value = Valuation.value(type: type, ageYears: listing.ageYears, condition: listing.condition)
            #expect(listing.rare == kind)
            #expect(listing.price == Int((Double(value) * RareFinds.priceShare(kind)).rounded()))
            switch kind {
            case .lowHours:
                #expect(listing.price < value)
                #expect(listing.condition >= 90 && listing.ageYears <= 5)
            case .heritage:
                #expect(listing.ageYears >= 25)
            case .barnFind:
                #expect(listing.price < value * 2 / 3)
                #expect(listing.condition <= 45)
            }
        }
    }

    @Test func buyingAHeritageFindPaintsTheAircraft() throws {
        var w = try Fixtures.world()
        w.airline.cash = 100_000_000
        let idFound = w.addRareFind(.heritage)
        let id = try #require(idFound)
        let planeID = try w.buyUsed(listingID: id)
        let plane = try #require(w.aircraft.first { $0.id == planeID })
        let livery = try #require(plane.livery)
        #expect(livery.name == RareFinds.heritageLiveryCode)
        #expect(livery.branding.primary != w.airline.branding.primary || livery.branding.style != w.airline.branding.style)
        #expect(!w.market.listings.contains { $0.id == id })
    }

    @Test func buyingAnOrdinaryFindKeepsTheAirlineLivery() throws {
        var w = try Fixtures.world()
        w.airline.cash = 100_000_000
        let idFound = w.addRareFind(.lowHours)
        let id = try #require(idFound)
        let planeID = try w.buyUsed(listingID: id)
        #expect(w.aircraft.first { $0.id == planeID }?.livery == nil)
    }

    @Test func aListingWithoutRareDecodes() throws {
        let json = "{\"id\":3,\"typeID\":\"c208\",\"ageYears\":12.5,\"condition\":80,\"price\":1500000,\"deliveryDays\":4}"
        let listing = try JSONDecoder().decode(UsedListing.self, from: Data(json.utf8))
        #expect(listing.id == 3)
        #expect(listing.rare == nil && listing.rareUntilDay == nil)
    }

    @Test func aRareListingSurvivesASaveAndLoad() throws {
        var w = try Fixtures.world()
        let idFound = w.addRareFind(.heritage)
        let id = try #require(idFound)
        let back = try JSONDecoder().decode(World.self, from: Fixtures.encode(w))
        #expect(back.market.listings.first { $0.id == id }?.rare == .heritage)
    }
}
