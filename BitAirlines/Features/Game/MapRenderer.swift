import SwiftUI
import UIKit
import CoreCatalog
import CoreSim
import CoreWorld

/// Where the map is looking: a centre and a zoom in screen points per degree of latitude.
struct MapCamera: Equatable {
    var lat: Double
    var lon: Double
    var ppd: Double

    static let minPPD = 1.6
    static let maxPPD = 120.0

    mutating func clamp() {
        ppd = min(Self.maxPPD, max(Self.minPPD, ppd))
        lat = min(85, max(-85, lat))
        lon = Self.wrap(lon)
    }

    static func wrap(_ lon: Double) -> Double {
        var l = (lon + 180).truncatingRemainder(dividingBy: 360)
        if l < 0 { l += 360 }
        return l - 180
    }
}

/// Maps between degrees and screen points for one camera and view size. Local equirectangular: east-west is squeezed by cos(latitude of the centre).
struct MapProjection {
    let camera: MapCamera
    let size: CGSize
    private let kx: Double
    private let ky: Double

    init(camera: MapCamera, size: CGSize) {
        self.camera = camera
        self.size = size
        ky = camera.ppd
        kx = camera.ppd * max(0.15, GeoMath.cosine(camera.lat * 3.141592653589793 / 180))
    }

    func point(lat: Double, lon: Double) -> CGPoint {
        var dLon = lon - camera.lon
        if dLon > 180 { dLon -= 360 }
        if dLon < -180 { dLon += 360 }
        return CGPoint(x: size.width / 2 + CGFloat(dLon * kx), y: size.height / 2 - CGFloat((lat - camera.lat) * ky))
    }

    func coordinate(at p: CGPoint) -> (lat: Double, lon: Double) {
        let lon = camera.lon + Double(p.x - size.width / 2) / kx
        let lat = camera.lat - Double(p.y - size.height / 2) / ky
        return (lat, MapCamera.wrap(lon))
    }

    func point(for airport: Airport) -> CGPoint { point(lat: airport.latitude, lon: airport.longitude) }

    var visible: CGRect { CGRect(origin: .zero, size: size).insetBy(dx: -30, dy: -30) }
}

enum MapPalette {
    static let deepWater = Color(hex: 0x0F1B3D)
    static let shallowWater = Color(hex: 0x1A3A6B)
    static let snow = Color(hex: 0xE3ECF7)
    static let snowShade = Color(hex: 0xC9D8EA)
    static let tundra = Color(hex: 0x7C8D6C)
    static let tundraShade = Color(hex: 0x6D7E5E)
    static let forest = Color(hex: 0x2E6B3A)
    static let forestShade = Color(hex: 0x3A7D44)
    static let grass = Color(hex: 0x5E9B45)
    static let grassShade = Color(hex: 0x6FAE4F)
    static let dry = Color(hex: 0xC2A664)
    static let dryShade = Color(hex: 0xB59A58)
    static let jungle = Color(hex: 0x1E6B3A)
    static let jungleShade = Color(hex: 0x2A7D45)

    /// 0 jungle, 1 dry, 2 grass, 3 forest, 4 tundra, 5 snow, by distance from the equator.
    static func category(latitude: Double) -> Int {
        let a = abs(latitude)
        if a >= 70 { return 5 }
        if a >= 60 { return 4 }
        if a >= 45 { return 3 }
        if a >= 30 { return 2 }
        if a >= 15 { return 1 }
        return 0
    }

    static func land(category: Int, shade: Bool) -> Color {
        switch category {
        case 5: return shade ? snowShade : snow
        case 4: return shade ? tundraShade : tundra
        case 3: return shade ? forestShade : forest
        case 2: return shade ? grassShade : grass
        case 1: return shade ? dryShade : dry
        default: return shade ? jungleShade : jungle
        }
    }
}

/// Draws the world: land and sea as chunky pixels straight from the land mask, then routes, airports and aircraft.
enum MapRenderer {
    /// Map pixel size in points for a zoom: never finer than 3 points, never coarser than one mask cell.
    static func cellSize(ppd: Double) -> CGFloat {
        let maskCell = 0.125 * ppd
        return CGFloat(max(3.0, maskCell))
    }

    static func drawTerrain(_ context: inout GraphicsContext, projection p: MapProjection) {
        let cell = cellSize(ppd: p.camera.ppd)
        let mask = LandMask.world
        let cols = Int(p.size.width / cell) + 2, rows = Int(p.size.height / cell) + 2
        var water = Path(), shallow = Path()
        var land: [Int: Path] = [:]
        var landColors: [Int: Color] = [:]

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
                    let category = MapPalette.category(latitude: c.lat)
                    let band = category * 2 + (shade ? 1 : 0)
                    if landColors[band] == nil { landColors[band] = MapPalette.land(category: category, shade: shade); land[band] = Path() }
                    land[band]?.addRect(rect)
                } else {
                    let near = grid[(gy + 1) * (cols + 2) + gx] || grid[(gy + 1) * (cols + 2) + gx + 2] || grid[gy * (cols + 2) + gx + 1] || grid[(gy + 2) * (cols + 2) + gx + 1]
                    if near { shallow.addRect(rect) } else { water.addRect(rect) }
                }
            }
        }
        context.fill(water, with: .color(MapPalette.deepWater), style: FillStyle(antialiased: false))
        context.fill(shallow, with: .color(MapPalette.shallowWater), style: FillStyle(antialiased: false))
        for (band, path) in land { context.fill(path, with: .color(landColors[band] ?? MapPalette.grass), style: FillStyle(antialiased: false)) }
    }

    /// Which airports to draw at a zoom, so the world view is not a smear of dots.
    static func shows(_ a: Airport, ppd: Double, important: Set<String>) -> Bool {
        if important.contains(a.code) { return true }
        if ppd >= 40 { return true }
        if ppd >= 14 { return a.scheduled || a.kind == .large || a.kind == .medium }
        if ppd >= 5 { return a.kind == .large || a.population > 300_000 }
        return a.kind == .large && a.population > 2_500_000
    }

    static func drawRoutes(_ context: inout GraphicsContext, world: World, projection p: MapProjection) {
        let colour = Livery.color(world.airline.branding.primary)
        for route in world.routes {
            for leg in route.legs {
                guard let a = AirportCatalog.airport(leg.from), let b = AirportCatalog.airport(leg.to) else { continue }
                var line = Path()
                line.move(to: p.point(for: a))
                line.addLine(to: p.point(for: b))
                context.stroke(line, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                context.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: [6, 3]))
            }
        }
    }

    /// Whether an airport earns a name label at this zoom (more labels as the map zooms in).
    static func wantsLabel(_ a: Airport, ppd: Double, mine: Bool) -> Bool {
        if mine { return true }
        if ppd >= 45 { return true }
        if ppd >= 20 { return a.scheduled || a.kind != .small }
        if ppd >= 10 { return a.kind == .large || a.population > 100_000 }
        return false
    }

    static func drawAirports(_ context: inout GraphicsContext, world: World, projection p: MapProjection, important: Set<String>, selected: Set<String>, labels: Bool) {
        let rect = p.visible
        var inView: [(airport: Airport, point: CGPoint)] = []
        for a in AirportCatalog.all where shows(a, ppd: p.camera.ppd, important: important) {
            let pt = p.point(for: a)
            if rect.contains(pt) { inView.append((airport: a, point: pt)) }
        }
        for item in inView {
            let a = item.airport, pt = item.point
            let size: CGFloat = a.kind == .large ? 6 : (a.kind == .medium ? 5 : 4)
            let isMine = important.contains(a.code)
            let fill: Color = isMine ? Theme.gold : (a.kind == .seaplane ? Theme.info : (a.scheduled ? Theme.textPrimary : Theme.textMuted))
            let box = CGRect(x: pt.x - size / 2, y: pt.y - size / 2, width: size, height: size)
            context.fill(Path(box.insetBy(dx: -1, dy: -1)), with: .color(.black.opacity(0.7)), style: FillStyle(antialiased: false))
            context.fill(Path(box), with: .color(fill), style: FillStyle(antialiased: false))
            if selected.contains(a.code) { context.stroke(Path(box.insetBy(dx: -4, dy: -4)), with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2)) }
        }
        if labels {
            // Labels, most important first, skipping any that would land on one already drawn.
            func priority(_ a: Airport) -> Int {
                if selected.contains(a.code) { return 4 }
                if important.contains(a.code) { return 3 }
                return a.kind == .large ? 2 : (a.kind == .medium ? 1 : 0)
            }
            let ordered = inView.sorted { priority($0.airport) != priority($1.airport) ? priority($0.airport) > priority($1.airport) : $0.airport.population > $1.airport.population }
            var placed: [CGRect] = []
            for item in ordered {
                let a = item.airport, pt = item.point
                let mine = important.contains(a.code) || selected.contains(a.code)
                guard wantsLabel(a, ppd: p.camera.ppd, mine: mine) else { continue }
                let box = CGRect(x: pt.x + 6, y: pt.y - 6, width: CGFloat(a.code.count) * 7 + 4, height: 12)
                if !mine && placed.contains(where: { $0.intersects(box.insetBy(dx: -2, dy: -1)) }) { continue }
                placed.append(box)
                let text = Text(a.code).font(Theme.pixel(8)).foregroundColor(mine ? Theme.gold : Theme.textPrimary)
                context.draw(context.resolve(text), at: CGPoint(x: box.minX, y: pt.y), anchor: .leading)
            }
        }
        if let home = AirportCatalog.airport(world.airline.home) {
            let pt = p.point(for: home)
            context.stroke(Path(CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)), with: .color(Theme.gold), style: StrokeStyle(lineWidth: 2))
        }
    }

    static func drawAircraft(_ context: inout GraphicsContext, world: World, projection p: MapProjection) {
        let now = world.clock.minute
        for plane in world.aircraft {
            guard case .flying(let until) = plane.status, let flight = plane.flight,
                  let a = AirportCatalog.airport(flight.from), let b = AirportCatalog.airport(flight.to), let type = plane.type else { continue }
            let total = max(1, until - flight.departedMinute)
            let t = min(1, max(0, Double(now - flight.departedMinute) / Double(total)))
            var dLon = b.longitude - a.longitude
            if dLon > 180 { dLon -= 360 }
            if dLon < -180 { dLon += 360 }
            let lat = a.latitude + (b.latitude - a.latitude) * t
            let lon = MapCamera.wrap(a.longitude + dLon * t)
            let from = p.point(for: a), to = p.point(for: b)
            let pt = p.point(lat: lat, lon: lon)
            guard p.visible.contains(pt) else { continue }
            let angle = Double(atan2(to.x - from.x, -(to.y - from.y)))
            guard let icon = Livery.mapIcon(sizeClass: Livery.sizeClass(seats: type.seats), branding: plane.livery?.branding ?? world.airline.branding) else { continue }
            let scale: CGFloat = 3
            var c = context
            c.translateBy(x: pt.x, y: pt.y)
            c.rotate(by: .radians(angle))
            let resolved = c.resolve(Image(uiImage: icon).interpolation(.none))
            c.draw(resolved, in: CGRect(x: -icon.size.width * scale / 2, y: -icon.size.height * scale / 2, width: icon.size.width * scale, height: icon.size.height * scale))
        }
    }
}
