import SwiftUI
import CoreCatalog
import CoreSim

/// Moving the map so a few airports sit in the part of the screen no panel covers.
enum MapFraming {
    /// Width of the airport and route panels on the left of the map, with their padding.
    static let panelReserve: CGFloat = 8 + 340 + 8
    /// Height of the toolbar along the top of the map.
    static let toolbarReserve: CGFloat = 56

    /// The part of a map of this size that the panel (if shown) and the toolbar leave free.
    static func freeRect(size: CGSize, panelShown: Bool) -> CGRect {
        let left = panelShown && size.width > panelReserve + 200 ? panelReserve : 8
        return CGRect(x: left, y: toolbarReserve, width: max(0, size.width - left - 8), height: max(0, size.height - toolbarReserve - 8))
    }

    /// True when every airport is inside the free part of the map for this camera.
    static func allVisible(_ airports: [Airport], camera: MapCamera, size: CGSize, free: CGRect) -> Bool {
        let projection = MapProjection(camera: camera, size: size)
        let inner = free.insetBy(dx: 24, dy: 24)
        return airports.allSatisfy { inner.contains(projection.point(for: $0)) }
    }

    /// A camera that shows these airports in the middle of `free`, zoomed in no closer than `maxPPD`. Nil if there is nothing to show.
    static func camera(showing airports: [Airport], size: CGSize, free: CGRect, maxPPD: Double = 60) -> MapCamera? {
        guard let first = airports.first, free.width > 40, free.height > 40 else { return nil }
        // Longitudes measured from the first airport, so two airports either side of the date line stay together.
        let lons = airports.map { airport -> Double in
            var d = airport.longitude - first.longitude
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            return first.longitude + d
        }
        let lats = airports.map(\.latitude)
        guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { return nil }
        let midLat = (south + north) / 2, midLon = (west + east) / 2
        let cosine = max(0.15, GeoMath.cosine(midLat * Double.pi / 180))
        let margin: CGFloat = 50
        let fitY = Double(max(40, free.height - 2 * margin)) / max(0.5, north - south)
        let fitX = Double(max(40, free.width - 2 * margin)) / (max(0.5, east - west) * cosine)
        var camera = MapCamera(lat: midLat, lon: midLon, ppd: min(maxPPD, fitX, fitY))
        camera.clamp()
        // Shift the centre so the airports land in the middle of the free part, not the middle of the whole map.
        camera.lon = midLon - Double(free.midX - size.width / 2) / (camera.ppd * cosine)
        camera.lat = midLat + Double(free.midY - size.height / 2) / camera.ppd
        camera.clamp()
        return camera
    }
}
