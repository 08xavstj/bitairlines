import SwiftUI
import UIKit
import CoreCatalog

/// AirportCatalog.all sorted once into 5 degree squares, so the map only looks at the squares on screen.
enum AirportIndex {
    static let degrees = 5.0
    static let rows = 36
    static let columns = 72

    /// For each square, positions in AirportCatalog.all.
    static let buckets: [[Int]] = {
        var b = [[Int]](repeating: [], count: AirportIndex.rows * AirportIndex.columns)
        for (i, a) in AirportCatalog.all.enumerated() {
            b[AirportIndex.row(a.latitude) * AirportIndex.columns + AirportIndex.column(a.longitude)].append(i)
        }
        return b
    }()

    static func row(_ lat: Double) -> Int {
        min(rows - 1, max(0, Int(((lat + 90) / degrees).rounded(.down))))
    }

    static func column(_ lon: Double) -> Int {
        min(columns - 1, max(0, Int(((MapCamera.wrap(lon) + 180) / degrees).rounded(.down))))
    }

    /// Airports between two latitudes and from a western longitude eastward over `span` degrees, in catalogue order.
    static func airports(south: Double, north: Double, west: Double, span: Double) -> [Airport] {
        let count = min(columns, Int((max(0, span) / degrees).rounded(.down)) + 2)
        let first = column(west)
        var found: [Int] = []
        for r in row(min(south, north))...row(max(south, north)) {
            for step in 0..<count { found.append(contentsOf: buckets[r * columns + (first + step) % columns]) }
        }
        found.sort()
        let all = AirportCatalog.all
        return found.map { all[$0] }
    }
}

/// Where the airports and their names go for one camera: worked out once, then drawn and tapped until something changes.
struct MapAirportLayout {
    struct Dot {
        let airport: Airport
        let point: CGPoint
        let mine: Bool
        let selected: Bool
    }

    struct Label {
        let text: String
        /// The left end of the text, at the height of the airport.
        let origin: CGPoint
        let mine: Bool
    }

    var dots: [Dot]
    var labels: [Label]

    static let empty = MapAirportLayout(dots: [], labels: [])

    /// `blocked` are screen areas covered by buttons and panels: no label goes under them.
    static func build(projection p: MapProjection, important: Set<String>, selected: Set<String>, blocked: [CGRect], widths: inout [String: CGFloat]) -> MapAirportLayout {
        let rect = p.visible
        let northWest = p.coordinate(at: CGPoint(x: rect.minX, y: rect.minY))
        let south = p.coordinate(at: CGPoint(x: rect.minX, y: rect.maxY)).lat
        let span = p.degreesOfLongitude(across: rect.width)
        let candidates = AirportIndex.airports(south: south - 0.01, north: northWest.lat + 0.01, west: northWest.lon - 0.01, span: span + 0.02)

        var dots: [Dot] = []
        for a in candidates where MapRenderer.shows(a, ppd: p.camera.ppd, important: important) {
            let pt = p.point(for: a)
            if rect.contains(pt) { dots.append(Dot(airport: a, point: pt, mine: important.contains(a.code), selected: selected.contains(a.code))) }
        }

        // Labels, most important first, skipping any that would land on one already placed, run off the screen or sit under a button.
        func priority(_ d: Dot) -> Int {
            if d.selected { return 4 }
            if d.mine { return 3 }
            return d.airport.kind == .large ? 2 : (d.airport.kind == .medium ? 1 : 0)
        }
        let ordered = dots.sorted { priority($0) != priority($1) ? priority($0) > priority($1) : $0.airport.population > $1.airport.population }
        let screen = CGRect(origin: .zero, size: p.size)
        var placed: [CGRect] = []
        var labels: [Label] = []
        for d in ordered {
            let mine = d.mine || d.selected
            guard MapRenderer.wantsLabel(d.airport, ppd: p.camera.ppd, mine: mine) else { continue }
            let text = d.airport.label
            let width = widths[text] ?? textWidth(text)
            widths[text] = width
            // The box covers the text and its one-point black outline. The name goes right of the dot, or left of it
            // when the right side runs off the screen, sits under a button or hits a name already placed.
            let right = CGRect(x: d.point.x + 5, y: d.point.y - 6, width: width + 2, height: 12)
            let left = CGRect(x: d.point.x - 7 - width, y: d.point.y - 6, width: width + 2, height: 12)
            var chosen: CGRect?
            for box in [right, left] {
                if !screen.contains(box) { continue }
                if blocked.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(box) }) { continue }
                if !mine && placed.contains(where: { $0.intersects(box.insetBy(dx: -2, dy: -1)) }) { continue }
                chosen = box
                break
            }
            guard let box = chosen else { continue }
            placed.append(box)
            labels.append(Label(text: text, origin: CGPoint(x: box.minX + 1, y: d.point.y), mine: mine))
        }
        return MapAirportLayout(dots: dots, labels: labels)
    }

    /// The width of a label in the map's 8 point pixel font.
    static func textWidth(_ text: String) -> CGFloat {
        let font = PixelFont.uiFont(8)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
