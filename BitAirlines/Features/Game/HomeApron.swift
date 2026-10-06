import SwiftUI
import UIKit
import CoreCatalog
import CoreWorld

/// The home airport in pixels: the terminal and tower, a hangar and fuel tank if they have been built, the aircraft on the ground at
/// home parked at their stands, a fuel truck doing its rounds and, now and then, an aircraft rolling down the runway.
struct HomeApron: View {
    let session: GameSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let world = session.world
        let home = world.airline.home
        let base = world.ops.bases.first { $0.airport == home }
        let parked = world.aircraft.filter { plane in
            guard plane.location == home, plane.isDelivered else { return false }
            if case .flying = plane.status { return false }
            return true
        }
        // The painter draws as many as fit the width and counts the rest; more than 8 would never fit.
        let images: [UIImage] = parked.prefix(8).compactMap { plane in
            plane.type.flatMap { Livery.image(family: $0.family, branding: plane.livery?.branding ?? world.airline.branding) }
        }
        let rolling = world.aircraft.first { if case .flying = $0.status { return $0.flight?.from == home } else { return false } }
        let rollImage = rolling.flatMap { plane in plane.type.flatMap { Livery.image(family: $0.family, branding: plane.livery?.branding ?? world.airline.branding) } }
        TimelineView(.animation(minimumInterval: reduceMotion ? 10 : 1.0 / 12.0)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                ApronPainter(size: size, t: t, code: world.airline.code, hasHangar: base?.has(.hangar) == true, hasDepot: base?.has(.fuelDepot) == true,
                             hasLights: base?.has(.lights) == true).paint(&context, parked: images, parkedCount: parked.count, rolling: rollImage)
            }
        }
        .accessibilityLabel("\(Place.name(home)) with \(parked.count) aircraft on the ground")
    }
}

/// Draws the apron. Pixel blocks only, so it matches the rest of the game.
struct ApronPainter {
    let size: CGSize
    let t: Double
    let code: String
    let hasHangar: Bool
    let hasDepot: Bool
    let hasLights: Bool

    private let px: CGFloat = 3
    private let tarmac = Color(hex: 0x2B3350)
    private let grass = Color(hex: 0x1E4A2E)
    private let line = Color(hex: 0xFFD166)
    private let wall = Color(hex: 0x5A6482)
    private let window = Color(hex: 0x8FB8FF)

    /// Parked aircraft are drawn larger when the sprite is small.
    private func standScale(_ image: UIImage) -> CGFloat { image.size.width > 70 ? 1.5 : 2 }

    /// How many parked aircraft fit side by side, leaving room for the "+N more" label when some do not.
    private func standsThatFit(_ parked: [UIImage], parkedCount: Int) -> Int {
        let gap: CGFloat = 12
        var count = 0
        var used: CGFloat = 0
        for image in parked {
            let next = used + image.size.width * standScale(image) + gap
            let left = parkedCount - (count + 1)
            if next > size.width - 40 - (left > 0 ? 70 : 0) { break }
            used = next
            count += 1
        }
        return count
    }

    private func block(_ context: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        context.fill(Path(CGRect(x: (x / px).rounded() * px, y: (y / px).rounded() * px, width: w, height: h)), with: .color(color), style: FillStyle(antialiased: false))
    }

    /// `parkedCount` is every aircraft on the ground at home; the ones that do not fit are shown as "+3 more".
    func paint(_ context: inout GraphicsContext, parked: [UIImage], parkedCount: Int, rolling: UIImage?) {
        let w = size.width, h = size.height
        let runwayY = h - 30
        // Sky is the panel; grass, apron and runway are bands.
        block(&context, 0, h * 0.42, w, h * 0.58, grass)
        block(&context, 0, h * 0.42, w, h * 0.30, tarmac)
        block(&context, 0, runwayY, w, 18, tarmac)
        var x: CGFloat = 6
        while x < w { block(&context, x, runwayY + 8, 12, 3, Color.white.opacity(0.75)); x += 30 }
        if hasLights {
            let on = Int(t * 2) % 2 == 0
            var lx: CGFloat = 3
            while lx < w { block(&context, lx, runwayY - 3, 3, 3, on ? line : line.opacity(0.4)); lx += 24 }
        }

        // Terminal with windows and the airline's code, and the tower with a blinking beacon.
        let termX: CGFloat = 12, termY = h * 0.42 - 42
        block(&context, termX, termY, 120, 42, wall)
        for wx in stride(from: termX + 6, to: termX + 114, by: 12) { block(&context, wx, termY + 15, 6, 9, window) }
        context.draw(Text(code).font(Theme.pixel(10.667)).foregroundStyle(Theme.gold), at: CGPoint(x: termX + 60, y: termY + 7))
        block(&context, termX + 128, termY - 30, 12, 72, wall)
        block(&context, termX + 122, termY - 42, 24, 12, window)
        if Int(t * 1.5) % 2 == 0 { block(&context, termX + 132, termY - 48, 3, 3, Theme.bad) }

        // Hangar and fuel tank, when built.
        var rightX = w - 12
        if hasHangar {
            rightX -= 96
            block(&context, rightX, h * 0.42 - 51, 96, 51, Color(hex: 0x9AA7C2))
            block(&context, rightX + 6, h * 0.42 - 57, 84, 6, Color(hex: 0x9AA7C2))
            block(&context, rightX + 12, h * 0.42 - 39, 72, 39, Color(hex: 0x141C33))
            rightX -= 12
        }
        if hasDepot {
            rightX -= 36
            block(&context, rightX, h * 0.42 - 30, 36, 30, Color(hex: 0xD7DEEE))
            block(&context, rightX, h * 0.42 - 18, 36, 6, Theme.bad)
        }

        // Aircraft at their stands: only as many as fit inside the canvas, then a count of the rest.
        let shown = standsThatFit(parked, parkedCount: parkedCount)
        let extra = parkedCount - shown
        let room = w - 40 - (extra > 0 ? 70 : 0)
        let stand = room / CGFloat(max(1, shown))
        for (n, image) in parked.prefix(shown).enumerated() {
            let scale = standScale(image)
            let iw = image.size.width * scale, ih = image.size.height * scale
            let cx = 20 + stand * CGFloat(n) + stand / 2
            let rect = CGRect(x: (cx - iw / 2).rounded(), y: (h * 0.72 - ih).rounded(), width: iw, height: ih)
            context.draw(Image(uiImage: image).interpolation(.none), in: rect)
        }
        if extra > 0 {
            context.draw(Text("+\(extra) MORE").font(Theme.pixel(10.667)).foregroundStyle(Theme.gold), at: CGPoint(x: w - 50, y: h * 0.72 - 12))
        }

        // A fuel truck driving back and forth along the apron.
        let lap = (t / 9).truncatingRemainder(dividingBy: 2)
        let truckX = 20 + (w - 60) * CGFloat(lap < 1 ? lap : 2 - lap)
        block(&context, truckX, h * 0.72 - 9, 24, 9, Color(hex: 0xD7DEEE))
        block(&context, truckX + (lap < 1 ? 18 : 0), h * 0.72 - 12, 6, 6, window)
        block(&context, truckX + 3, h * 0.72, 6, 3, Color.black)
        block(&context, truckX + 15, h * 0.72, 6, 3, Color.black)

        // An aircraft that has just left home rolls down the runway.
        if let rolling {
            let roll = CGFloat((t / 5).truncatingRemainder(dividingBy: 1))
            let iw = rolling.size.width * 1.5, ih = rolling.size.height * 1.5
            let rect = CGRect(x: (-iw + (w + iw) * roll).rounded(), y: (runwayY + 12 - ih - roll * 20).rounded(), width: iw, height: ih)
            context.draw(Image(uiImage: rolling).interpolation(.none), in: rect)
        }
    }
}

/// The next few departures from home, like the board in the terminal.
struct DeparturesBoard: View {
    let world: World

    var body: some View {
        let home = world.airline.home
        let rows: [(time: Int, text: String)] = world.aircraft.compactMap { plane in
            guard plane.location == home, case .boarding(let until) = plane.status else { return nil }
            if let jobID = plane.jobID, let job = world.ops.jobs.first(where: { $0.id == jobID }) { return (until, "\(plane.registration)  \(Words.name(job.kind)) to \(Place.name(job.to))") }
            guard let rid = plane.routeID, let route = world.routes.first(where: { $0.id == rid }), let l = route.firstLeg(from: home) else { return nil }
            return (until, "\(plane.registration)  to \(Place.name(route.legs[l].to))")
        }.sorted { $0.time < $1.time }
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEPARTURES FROM \(Place.name(home).uppercased())").pixelFont(10.667).foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
                if rows.isEmpty { Text("Nothing waiting to leave home right now.").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
                ForEach(Array(rows.prefix(5).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(Format.time(GameClock(minute: max(row.time, world.clock.minute)))).pixelFont(10.667).foregroundStyle(Theme.gold).frame(width: 60, alignment: .leading)
                        Text(row.text).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if rows.count > 5 {
                    Text("and \(rows.count - 5) more").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }
}
