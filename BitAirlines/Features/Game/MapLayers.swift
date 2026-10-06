import SwiftUI

/// One leg of a route on the map: just the two airports, so the layer below can tell when the network really changed.
struct MapLeg: Equatable {
    let from: String
    let to: String
}

/// The parts of the map that stay still while the clock runs: terrain, route lines, the route being planned, airports and their names.
/// It is Equatable (the cache is left out), so with `.equatable()` the clock ticking does not redraw it; only the aircraft layer redraws.
struct MapStillLayer: View, Equatable {
    let camera: MapCamera
    let legs: [MapLeg]
    /// The airline colour (a palette index) for the route lines.
    let routePalette: Int
    let home: String
    let important: Set<String>
    let marked: Set<String>
    /// The stops of the route being planned, or empty.
    let plan: [String]
    /// A leg of the plan none of the player's aircraft can fly (index into `plan`), drawn in the warning colour.
    var planBlocked: Int? = nil
    let blocked: [CGRect]
    let cache: MapCache
    @Environment(\.displayScale) private var displayScale

    nonisolated static func == (a: MapStillLayer, b: MapStillLayer) -> Bool {
        a.camera == b.camera && a.legs == b.legs && a.routePalette == b.routePalette && a.home == b.home
            && a.important == b.important && a.marked == b.marked && a.plan == b.plan && a.planBlocked == b.planBlocked && a.blocked == b.blocked
    }

    var body: some View {
        Canvas { context, size in
            guard size.width >= 1, size.height >= 1 else { return }
            let projection = MapProjection(camera: camera, size: size)
            MapRenderer.drawTerrain(&context, image: cache.terrain(projection: projection, scale: displayScale), size: size)
            MapRenderer.drawRoutes(&context, legs: legs, colour: Livery.color(routePalette), projection: projection)
            if plan.count >= 2 { MapRenderer.drawPlan(&context, stops: plan, blockedLeg: planBlocked, projection: projection) }
            let layout = cache.airports(projection: projection, important: important, selected: marked, blocked: blocked)
            MapRenderer.drawAirports(&context, layout: layout, home: home, projection: projection)
        }
    }
}

/// Collects the frames of the buttons and panels drawn over the map, so no airport name hides under them.
struct MapOverlayFramesKey: PreferenceKey {
    static let space = "map"
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}

/// Collects the frames of the see-through hints over the map (the NEXT line). No airport name goes under them,
/// but unlike buttons and panels they let taps through to the map.
struct MapHintFramesKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}

extension View {
    /// Marks this view as covering part of the map: names stay out from under it and taps on it are not for the map.
    func coversMap() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: MapOverlayFramesKey.self, value: [geo.frame(in: .named(MapOverlayFramesKey.space))])
        })
    }

    /// Marks this view as a hint over the map: names stay out from under it, but taps, drags and pinches go through to the map.
    func hintsOverMap() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: MapHintFramesKey.self, value: [geo.frame(in: .named(MapOverlayFramesKey.space))])
        })
        .allowsHitTesting(false)
    }
}
