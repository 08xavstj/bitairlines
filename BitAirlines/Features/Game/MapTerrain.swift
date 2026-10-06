import SwiftUI
import UIKit
import CoreCatalog

/// Paints the land and sea into one picture for a camera and view size: chunky pixels straight from the land mask.
/// The map keeps the picture in `MapCache` and only paints a new one when the camera or the size changes.
enum MapTerrain {
    static func render(projection p: MapProjection, scale: CGFloat) -> UIImage {
        let cell = MapRenderer.cellSize(ppd: p.camera.ppd)
        let mask = LandMask.world
        let cols = Int(p.size.width / cell) + 2, rows = Int(p.size.height / cell) + 2
        var water: [CGRect] = [], shallow: [CGRect] = []
        var land: [Int: [CGRect]] = [:]

        func isLand(_ gx: Int, _ gy: Int) -> Bool {
            let c = p.coordinate(at: CGPoint(x: (CGFloat(gx) + 0.5) * cell, y: (CGFloat(gy) + 0.5) * cell))
            return mask.isLand(latitude: c.lat, longitude: c.lon)
        }

        var grid = [Bool](repeating: false, count: (cols + 2) * (rows + 2))
        for gy in -1...rows {
            for gx in -1...cols { grid[(gy + 1) * (cols + 2) + (gx + 1)] = isLand(gx, gy) }
        }
        for gy in 0..<rows {
            for gx in 0..<cols {
                let rect = CGRect(x: CGFloat(gx) * cell, y: CGFloat(gy) * cell, width: cell + 0.5, height: cell + 0.5)
                let here = grid[(gy + 1) * (cols + 2) + (gx + 1)]
                if here {
                    let c = p.coordinate(at: CGPoint(x: (CGFloat(gx) + 0.5) * cell, y: (CGFloat(gy) + 0.5) * cell))
                    let hash = (gx &* 73856093) ^ (gy &* 19349663)
                    let shade = UInt(bitPattern: hash) % 3 == 0
                    let band = MapPalette.category(latitude: c.lat) * 2 + (shade ? 1 : 0)
                    land[band, default: []].append(rect)
                } else {
                    let near = grid[(gy + 1) * (cols + 2) + gx] || grid[(gy + 1) * (cols + 2) + gx + 2] || grid[gy * (cols + 2) + gx + 1] || grid[(gy + 2) * (cols + 2) + gx + 1]
                    if near { shallow.append(rect) } else { water.append(rect) }
                }
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let size = CGSize(width: max(1, p.size.width), height: max(1, p.size.height))
        return UIGraphicsImageRenderer(size: size, format: format).image { drawing in
            let cg = drawing.cgContext
            cg.setShouldAntialias(false)
            paint(cg, water, MapPalette.deepWater)
            paint(cg, shallow, MapPalette.shallowWater)
            for band in land.keys.sorted() {
                paint(cg, land[band] ?? [], MapPalette.land(category: band / 2, shade: band % 2 == 1))
            }
        }
    }

    private static func paint(_ cg: CGContext, _ rects: [CGRect], _ colour: Color) {
        guard !rects.isEmpty else { return }
        cg.setFillColor(UIColor(colour).cgColor)
        cg.fill(rects)
    }
}
