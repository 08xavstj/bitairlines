import Testing
import CoreCatalog
@testable import CoreWorld

@Suite struct FleetBalanceTests {
    /// Four Caravans on thin Inuvik - Tuktoyaktuk, and Inuvik - Mayo with none.
    func crowdedWorld() throws -> (world: World, thin: Int, busy: Int) {
        var w = try Fixtures.world()
        let thin = try w.createRoute(stops: ["YEV", "YUB"])
        let busy = try w.createRoute(stops: ["YEV", "YMA"])
        for k in 0..<3 {
            w.aircraft.append(Aircraft(id: 600 + k, typeID: "c208", registration: "C-FSP\(k)", builtDay: 0, condition: 90, price: 3_000_000,
                                       location: "YEV", status: .idle))
        }
        for id in w.aircraft.map(\.id) { try w.assign(aircraftID: id, toRoute: thin) }
        return (w, thin, busy)
    }

    func count(_ w: World, _ routeID: Int) -> Int { w.routes.first(where: { $0.id == routeID })?.aircraftIDs.count ?? 0 }

    @Test func spareAircraftMoveAndTheOldRouteKeepsEnough() throws {
        var (w, thin, busy) = try crowdedWorld()
        let needed = try #require(w.aircraftNeeded(routeID: thin))
        #expect(needed < 4)
        let spare = w.spareAircraft(routeID: thin)
        #expect(spare.count == 4 - needed)
        let moves = try w.moveSpareAircraft(routeID: thin)
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0.toRouteID == busy && $0.fromRouteID == thin })
        #expect(count(w, thin) >= needed)
        #expect(count(w, thin) == 4 - moves.count)
        #expect(count(w, busy) == moves.count)
        #expect(w.news.contains { $0.kind == .fleetMoved })
    }

    @Test func withNowhereBetterTheAircraftStay() throws {
        var (w, thin, busy) = try crowdedWorld()
        try w.deleteRoute(id: busy)
        let moves = try w.moveSpareAircraft(routeID: thin)
        #expect(moves.isEmpty)
        #expect(count(w, thin) == 4)
    }

    @Test func theFleetPlannerMovesSparesOnMonday() throws {
        var (w, thin, busy) = try crowdedWorld()
        try w.hire(.fleetPlanner)
        w.weeklyStaff()
        #expect(count(w, busy) > 0)
        #expect(count(w, thin) >= (w.aircraftNeeded(routeID: thin) ?? 1))
    }
}
