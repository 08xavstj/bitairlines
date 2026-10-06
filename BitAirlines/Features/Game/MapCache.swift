import SwiftUI
import UIKit

/// Remembers the slow parts of the map until something they depend on changes:
/// the terrain picture (camera and size) and the airport dots and labels (camera, size, network, selection and the buttons on top).
/// A class held in @State, so filling it while drawing does not make SwiftUI draw again.
final class MapCache {
    private struct TerrainKey: Equatable {
        let camera: MapCamera
        let size: CGSize
        let scale: CGFloat
    }

    private struct AirportKey: Equatable {
        let camera: MapCamera
        let size: CGSize
        let important: Set<String>
        let selected: Set<String>
        let blocked: [CGRect]
    }

    private var terrainKey: TerrainKey?
    private var terrainImage: UIImage?
    private var airportKey: AirportKey?
    private var airportLayout = MapAirportLayout.empty
    private var labelWidths: [String: CGFloat] = [:]

    func terrain(projection: MapProjection, scale: CGFloat) -> UIImage {
        let key = TerrainKey(camera: projection.camera, size: projection.size, scale: scale)
        if key == terrainKey, let image = terrainImage { return image }
        let image = MapTerrain.render(projection: projection, scale: scale)
        terrainKey = key
        terrainImage = image
        return image
    }

    func airports(projection: MapProjection, important: Set<String>, selected: Set<String>, blocked: [CGRect]) -> MapAirportLayout {
        let key = AirportKey(camera: projection.camera, size: projection.size, important: important, selected: selected, blocked: blocked)
        if key == airportKey { return airportLayout }
        airportLayout = MapAirportLayout.build(projection: projection, important: important, selected: selected, blocked: blocked, widths: &labelWidths)
        airportKey = key
        return airportLayout
    }
}
