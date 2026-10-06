import Foundation
import Testing
import CoreCatalog
@testable import CoreWorld

/// One aircraft flying up to three routes (SharedAircraft.swift).
@Suite struct SharedAircraftTests {
    /// True if every aircraft is listed on exactly the routes it flies, and every route lists only aircraft that fly it.
    static func consistent(_ w: World) -> Bool {
        for plane in w.aircraft {
            let flown = plane.allRouteIDs
            if Set(flown).count != flown.count { return false }
            if plane.routeID == nil && !plane.otherRouteIDs.isEmpty { return false }
            for rid in flown {
                guard let route = w.routes.first(where: { $0.id == rid }) else { return false }
                if route.aircraftIDs.filter({ $0 == plane.id }).count != 1 { return false }
            }
        }
        for route in w.routes {
            for id in route.aircraftIDs {
                guard let plane = w.aircraft.first(where: { $0.id == id }) else { return false }
                if !plane.allRouteIDs.contains(route.id) { return false }
            }
        }
        return true
    }

    /// Error thrown by addRoute, if any (kept out of #expect so no mutating call runs inside a macro).
    static func addRouteError(_ w: inout World, aircraftID: Int, routeID: Int) -> WorldError? {
        do {
            try w.addRoute(aircraftID: aircraftID, routeID: routeID)
            return nil
        } catch let error as WorldError {
            return error
        } catch {
            return .invalidChoice
        }
    }

    @Test func oneCaravanFliesTwoThinRoutes() throws {
        var w = try Fixtures.world()
        for code in ["YEV", "YUB", "YSY"] { Fixtures.light(&w, code) }
        let plane = w.aircraft[0].id
        let north = try w.createRoute(stops: ["YEV", "YUB"])
        let east = try w.createRoute(stops: ["YEV", "YSY"])
        try w.assign(aircraftID: plane, toRoute: north)
        try w.addRoute(aircraftID: plane, routeID: east)
        try w.setFrequency(routeID: north, perDay: 0.5)
        try w.setFrequency(routeID: east, perDay: 0.5)
        let flown = w.aircraft[0].allRouteIDs
        #expect(flown == [north, east])
        let listed = Self.consistent(w)
        #expect(listed)

        w.advance(byMinutes: 7 * 1440)
        let northFlights = w.routes.first { $0.id == north }?.flights ?? 0
        let eastFlights = w.routes.first { $0.id == east }?.flights ?? 0
        #expect(northFlights > 0, "the first route is flown")
        #expect(eastFlights > 0, "the shared route fills the days the first one leaves the aircraft on the ground")
        let after = Self.consistent(w)
        #expect(after)
    }

    @Test func listsStayConsistentWhenRoutesAreDropped() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        let north = try w.createRoute(stops: ["YEV", "YUB"])
        let east = try w.createRoute(stops: ["YEV", "YSY"])
        let coast = try w.createRoute(stops: ["YUB", "YSY"])
        let loop = try w.createRoute(stops: ["YSY", "YUB", "YEV"])
        try w.assign(aircraftID: plane, toRoute: north)
        try w.addRoute(aircraftID: plane, routeID: east)
        try w.addRoute(aircraftID: plane, routeID: coast)
        let three = w.aircraft[0].allRouteIDs
        #expect(three == [north, east, coast])
        let fourth = Self.addRouteError(&w, aircraftID: plane, routeID: loop)
        #expect(fourth == .tooManyRoutes)
        let again = Self.addRouteError(&w, aircraftID: plane, routeID: east)
        #expect(again == .invalidChoice)
        let start = Self.consistent(w)
        #expect(start)

        // Dropping the current route promotes the next one.
        try w.removeRoute(aircraftID: plane, routeID: north)
        let afterRemove = w.aircraft[0].allRouteIDs
        #expect(afterRemove == [east, coast])
        let northPlanes = w.routes.first { $0.id == north }?.aircraftIDs ?? [-1]
        #expect(northPlanes.isEmpty)
        let removed = Self.consistent(w)
        #expect(removed)

        // Deleting a route the aircraft flies leaves it on the others.
        try w.deleteRoute(id: east)
        let afterDelete = w.aircraft[0].allRouteIDs
        #expect(afterDelete == [coast])
        let deleted = Self.consistent(w)
        #expect(deleted)

        // Assign means this route only.
        try w.addRoute(aircraftID: plane, routeID: north)
        try w.assign(aircraftID: plane, toRoute: loop)
        let only = w.aircraft[0].allRouteIDs
        #expect(only == [loop])
        let assigned = Self.consistent(w)
        #expect(assigned)

        // Unassign takes it off everything.
        try w.addRoute(aircraftID: plane, routeID: north)
        try w.unassign(aircraftID: plane)
        let none = w.aircraft[0].allRouteIDs
        #expect(none.isEmpty && w.aircraft[0].routeID == nil)
        let empty = w.routes.allSatisfy { $0.aircraftIDs.isEmpty }
        #expect(empty)
        let unassigned = Self.consistent(w)
        #expect(unassigned)
    }

    @Test func aSharedAircraftCountsAsAPartOfEachRoute() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        let north = try w.createRoute(stops: ["YEV", "YUB"])
        let east = try w.createRoute(stops: ["YEV", "YSY"])
        try w.assign(aircraftID: plane, toRoute: north)
        let alone = w.aircraftShare(onRoute: north)
        #expect(alone == 1)
        try w.addRoute(aircraftID: plane, routeID: east)
        let shared = w.aircraftShare(onRoute: north)
        let sharedEast = w.aircraftShare(onRoute: east)
        #expect(shared == 0.5 && sharedEast == 0.5)
    }

    @Test func addRouteRefusesARouteThatSharesNoAirport() throws {
        var w = try Fixtures.world()
        let plane = w.aircraft[0].id
        let coast = try w.createRoute(stops: ["YUB", "YSY"])
        let south = try w.createRoute(stops: ["YEV", "YZF"])
        let noRouteYet = Self.addRouteError(&w, aircraftID: plane, routeID: south)
        #expect(noRouteYet == .invalidChoice, "an aircraft needs a route before it can share")
        try w.assign(aircraftID: plane, toRoute: coast)
        let problem = w.addRouteProblem(aircraftID: plane, routeID: south)
        #expect(problem == .routesDoNotMeet)
        let refused = Self.addRouteError(&w, aircraftID: plane, routeID: south)
        #expect(refused == .routesDoNotMeet)
        let flown = w.aircraft[0].allRouteIDs
        #expect(flown == [coast])
        let offered = w.routesToShare(aircraftID: plane).map(\.id)
        #expect(offered.isEmpty)
    }

    @Test func anAircraftFromBeforeSharingStillLoads() throws {
        let w = try Fixtures.flyingWorld()
        var plane = w.aircraft[0]
        plane.otherRoutesStore = nil
        plane.returnOtherRoutesStore = nil
        let json = try JSONEncoder().encode(plane)
        let text = String(data: json, encoding: .utf8) ?? ""
        #expect(!text.contains("otherRoutesStore"))
        let loaded = try JSONDecoder().decode(Aircraft.self, from: json)
        #expect(loaded.otherRouteIDs.isEmpty)
        #expect(loaded.allRouteIDs == [w.routes[0].id])

        // A shared aircraft keeps its routes through a save.
        var shared = plane
        shared.otherRouteIDs = [5, 9]
        let back = try JSONDecoder().decode(Aircraft.self, from: JSONEncoder().encode(shared))
        #expect(back.otherRouteIDs == [5, 9])
    }
}
