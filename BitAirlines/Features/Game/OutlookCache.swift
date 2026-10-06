import CoreCatalog
import CoreWorld

/// Remembers the forecast shown on each route card, so it is not worked out again on every clock tick.
/// A forecast is made again only when something the player set on the route changes.
@MainActor
final class OutlookCache {
    static let shared = OutlookCache()

    /// What the forecast depends on that the player can change from the route card or the fleet.
    struct Key: Hashable {
        var routeID: Int
        var openedDay: Int
        var stops: [String]
        var frequency: Double
        var fare: Double
        var carriesCargo: Bool
        var service: ServiceLevel
        var aircraftIDs: [Int]
        var typeIDs: [String]
    }

    private var store: [Int: (key: Key, forecast: RouteForecast)] = [:]

    /// What the "on its own" forecast in the assign lists depends on: the route's settings, the aircraft type and the game day
    /// (the market moves day by day).
    struct AssignKey: Hashable {
        var routeID: Int
        var typeID: String
        var openedDay: Int
        var stops: [String]
        var frequency: Double
        var autoFrequency: Bool
        var fare: Double
        var carriesCargo: Bool
        var service: ServiceLevel
        var day: Int
    }

    private struct AssignSlot: Hashable {
        var routeID: Int
        var typeID: String
    }

    private var assignStore: [AssignSlot: (key: AssignKey, forecast: RouteForecast)] = [:]

    /// The forecast for one more aircraft of this type flying the route on its own (the assign lists), worked out again only when
    /// its inputs change.
    func assignForecast(world: World, route: Route, type: AircraftType) -> RouteForecast {
        let key = AssignKey(routeID: route.id, typeID: type.id, openedDay: route.openedDay, stops: route.stops, frequency: route.frequency,
                            autoFrequency: route.autoFrequency, fare: route.fareMultiplier, carriesCargo: route.carriesCargo, service: route.service,
                            day: world.clock.dayIndex)
        let slot = AssignSlot(routeID: route.id, typeID: type.id)
        if let saved = assignStore[slot], saved.key == key { return saved.forecast }
        let forecast = world.forecast(route: route, type: type, aircraftCount: 1, suggestedSchedule: route.autoFrequency)
        if assignStore.count > 500 { assignStore = [:] }
        assignStore[slot] = (key: key, forecast: forecast)
        return forecast
    }

    /// The forecast for a route with `planes` on it (all assumed to be the first one's type, as before).
    func forecast(world: World, route: Route, planes: [Aircraft], type: AircraftType) -> RouteForecast {
        let key = Key(routeID: route.id, openedDay: route.openedDay, stops: route.stops, frequency: route.frequency, fare: route.fareMultiplier,
                      carriesCargo: route.carriesCargo, service: route.service, aircraftIDs: route.aircraftIDs, typeIDs: planes.map { $0.typeID })
        if let saved = store[route.id], saved.key == key { return saved.forecast }
        let forecast = world.forecast(route: route, type: type, aircraftCount: planes.count)
        store[route.id] = (key: key, forecast: forecast)
        return forecast
    }
}
