import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct MarketingStaffTests {
    @Test func aCampaignCostsMoneyLiftsAwarenessAndEnds() throws {
        var w = try Fixtures.world()
        w.pausePolicy = .never
        #expect(w.campaignProblem(.radio) == .needsARoute)
        _ = try w.createRoute(stops: ["YEV", "YUB"])
        let before = w.routes[0].legs[0].maturity
        let cash = w.airline.cash
        try w.startCampaign(.radio)
        #expect(w.airline.cash == cash - w.campaignPrice(.radio))
        #expect(w.routes[0].legs[0].maturity > before)
        #expect(w.marketingFactor > 1.0)
        #expect(w.campaignProblem(.radio) == .campaignRunning)
        w.advance(byMinutes: (Tuning.campaignDays(.radio) + 1) * 1440)
        #expect(w.activeCampaign(.radio) == nil && w.marketingFactor == 1.0)
    }

    @Test func staffArePaidMonthlyAndCanBeLetGo() throws {
        var w = try Fixtures.world()
        try w.hire(.revenueManager)
        #expect(throws: WorldError.alreadyHired) { try w.hire(.revenueManager) }
        #expect(w.staffPayroll == w.staffSalary(.revenueManager))
        try w.dismiss(.revenueManager)
        #expect(w.staffPayroll == 0)
        #expect(throws: WorldError.notHired) { try w.dismiss(.revenueManager) }
    }

    @Test func theRevenueManagerRaisesFaresOnFullRoutes() throws {
        var w = try Fixtures.flyingWorld()
        w.pausePolicy = .never
        w.advance(byMinutes: 8 * 1440)
        let load = w.routes[0].seatLoadLast7Days ?? 0
        let fare = w.routes[0].fareMultiplier
        try w.hire(.revenueManager)
        w.manageFares()
        if load > Tuning.fareRaiseLoad { #expect(w.routes[0].fareMultiplier > fare) }
        else if load < Tuning.fareCutLoad { #expect(w.routes[0].fareMultiplier < fare) }
        else { #expect(w.routes[0].fareMultiplier == fare) }
        #expect(Tuning.managedFareRange.contains(w.routes[0].fareMultiplier))
    }

    @Test func theOperationsManagerSettlesABreakdownSoTheGameRunsOn() throws {
        var w = try Fixtures.world()
        try w.hire(.operationsManager)
        let type = try Fixtures.type("c208")
        w.raiseBreakdown(aircraftIndex: 0, type: type)
        #expect(!w.issues.contains { if case .breakdown = $0.kind { return true } else { return false } })
        #expect(!w.isPausedByIssue)
        var inRepair = false
        if case .maintenance = w.aircraft[0].status { inRepair = true }
        #expect(inRepair, "the aircraft should be in for repair")
    }

    @Test func theFleetPlannerPutsAParkedAircraftOnARoute() throws {
        var w = try Fixtures.world()
        _ = try w.createRoute(stops: ["YEV", "YUB"])
        #expect(w.aircraft[0].routeID == nil)
        try w.hire(.fleetPlanner)
        w.planFleet()
        #expect(w.aircraft[0].routeID == w.routes[0].id)
    }

    @Test func oldOperationsWithoutMarketingOrStaffStillLoad() throws {
        let loaded = try JSONDecoder().decode(Operations.self, from: Data("{}".utf8))
        #expect(loaded.staff.isEmpty && loaded.campaigns.isEmpty)
    }
}
