import SwiftUI
import Observation
import CoreCatalog

/// What the map remembers while the player looks at another screen: where the map looks, the airport that is open,
/// the route being planned and the airports another screen asked to see.
/// The game shell owns it (it is not saved), so going to the Hangar and back keeps all of it.
@MainActor
@Observable
final class MapState {
    var camera: MapCamera
    /// The airport whose panel is open.
    var selected: String?
    /// True while the route planner is open.
    var planning = false
    /// The stops of the route being planned, in order.
    var stops: [String] = []
    /// Airports another screen asked to see (a job's two ends), marked and named until the player moves on.
    var focus: [String] = []
    /// Terrain picture and airport layout, kept between frames and between visits to the map.
    @ObservationIgnored let cache = MapCache()

    init(home: String) {
        let airport = AirportCatalog.airport(home)
        camera = MapCamera(lat: airport?.latitude ?? 0, lon: airport?.longitude ?? 0, ppd: 30)
        #if DEBUG
        if let demoStops = Demo.plannerStops {
            planning = true
            stops = demoStops
        }
        if Demo.screen == "airport" { selected = home }
        #endif
    }

    /// Back to the home airport at the normal zoom.
    func goHome(_ home: String) {
        guard let airport = AirportCatalog.airport(home) else { return }
        focus = []
        camera = MapCamera(lat: airport.latitude, lon: airport.longitude, ppd: 30)
    }

    /// Opens the route planner, starting at `code` if given.
    func startPlan(from code: String?) {
        planning = true
        stops = code.map { [$0] } ?? []
        selected = nil
        focus = []
    }

    /// Closes the route planner and forgets its stops.
    func stopPlan() {
        planning = false
        stops = []
    }
}
