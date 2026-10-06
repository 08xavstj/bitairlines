import SwiftUI
import CoreCatalog
import CoreWorld

/// The world map: pan and zoom, tap airports, plan routes, watch the aircraft fly.
struct MapScreen: View {
    let session: GameSession
    @State private var camera: MapCamera
    @State private var dragStart: MapCamera?
    @State private var pinchStart: Double?
    @State private var selected: String?
    @State private var planning = false
    @State private var stops: [String] = []

    init(session: GameSession) {
        self.session = session
        let home = AirportCatalog.airport(session.world.airline.home)
        _camera = State(initialValue: MapCamera(lat: home?.latitude ?? 0, lon: home?.longitude ?? 0, ppd: 30))
    }

    var body: some View {
        let world = session.world
        let important = Set(world.routes.flatMap { $0.stops } + [world.airline.home])
        let marked = Set(stops + (selected.map { [$0] } ?? []))
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let projection = MapProjection(camera: camera, size: size)
                    MapRenderer.drawTerrain(&context, projection: projection)
                    MapRenderer.drawRoutes(&context, world: world, projection: projection)
                    if planning && stops.count >= 2 { drawPlan(&context, projection: projection) }
                    MapRenderer.drawAirports(&context, world: world, projection: projection, important: important, selected: marked, labels: true)
                    MapRenderer.drawAircraft(&context, world: world, projection: projection)
                }
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { pan($0, size: geo.size) }
                    .onEnded { _ in dragStart = nil })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { zoom(by: Double($0.magnification)) }
                    .onEnded { _ in pinchStart = nil })
                .simultaneousGesture(SpatialTapGesture().onEnded { tap(at: $0.location, size: geo.size, world: world) })

                toolbar
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(8)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 8) {
                        if planning {
                            RoutePlannerPanel(session: session, stops: $stops, onClose: { planning = false; stops = [] })
                        } else if let code = selected, let airport = AirportCatalog.airport(code) {
                            AirportPanel(world: world, airport: airport, onPlan: { startPlan(from: code) }, onClose: { selected = nil })
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(8)
            }
        }
        .background(Theme.background)
        .clipped()
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            PixelSquareButton(icon: .plus, label: "Zoom in") { zoom(factor: 1.6) }
            PixelSquareButton(icon: .minus, label: "Zoom out") { zoom(factor: 1 / 1.6) }
            Button("Home") { goHome() }.buttonStyle(.small)
            Button(planning ? "Cancel route" : "New route") {
                if planning { planning = false; stops = [] } else { startPlan(from: nil) }
            }.buttonStyle(planning ? AnyButtonStyle(SmallButtonStyle(kind: .danger)) : AnyButtonStyle(SmallButtonStyle(kind: .prominent)))
        }
    }

    private func goHome() {
        guard let home = AirportCatalog.airport(session.world.airline.home) else { return }
        camera = MapCamera(lat: home.latitude, lon: home.longitude, ppd: 30)
    }

    private func startPlan(from code: String?) {
        planning = true
        stops = code.map { [$0] } ?? []
        selected = nil
    }

    // MARK: Gestures

    private func pan(_ value: DragGesture.Value, size: CGSize) {
        if dragStart == nil { dragStart = camera }
        guard let start = dragStart else { return }
        let projection = MapProjection(camera: start, size: size)
        let centre = projection.coordinate(at: CGPoint(x: size.width / 2 - value.translation.width, y: size.height / 2 - value.translation.height))
        camera.lat = centre.lat
        camera.lon = centre.lon
        camera.clamp()
    }

    private func zoom(by magnification: Double) {
        if pinchStart == nil { pinchStart = camera.ppd }
        camera.ppd = (pinchStart ?? camera.ppd) * magnification
        camera.clamp()
    }

    private func zoom(factor: Double) {
        camera.ppd *= factor
        camera.clamp()
    }

    private func tap(at point: CGPoint, size: CGSize, world: World) {
        let projection = MapProjection(camera: camera, size: size)
        let important = Set(world.routes.flatMap { $0.stops } + [world.airline.home])
        var best: (code: String, distance: CGFloat)?
        for a in AirportCatalog.all where MapRenderer.shows(a, ppd: camera.ppd, important: important) {
            let p = projection.point(for: a)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < 24, best == nil || d < best!.distance { best = (a.code, d) }
        }
        guard let code = best?.code else {
            if !planning { selected = nil }
            return
        }
        if planning {
            if let i = stops.firstIndex(of: code) { stops.remove(at: i) } else if stops.count < World.maxStops { stops.append(code) }
        } else {
            selected = selected == code ? nil : code
        }
    }

    private func drawPlan(_ context: inout GraphicsContext, projection: MapProjection) {
        var path = Path()
        for (i, code) in stops.enumerated() {
            guard let a = AirportCatalog.airport(code) else { continue }
            if i == 0 { path.move(to: projection.point(for: a)) } else { path.addLine(to: projection.point(for: a)) }
        }
        if stops.count > 2, let first = AirportCatalog.airport(stops[0]) { path.addLine(to: projection.point(for: first)) }
        context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 3, dash: [2, 4]))
    }
}

/// Facts about the airport the player tapped.
struct AirportPanel: View {
    let world: World
    let airport: Airport
    let onPlan: () -> Void
    let onClose: () -> Void

    var body: some View {
        let required = Progression.requiredLevel(for: airport)
        let locked = required > world.airline.level && airport.code != world.airline.home
        let home = AirportCatalog.airport(world.airline.home)
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(airport.label.uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent).lineLimit(1)
                    Spacer()
                    PixelSquareButton(icon: .close, label: "Close", action: onClose)
                }
                Text(airport.name).pixelFont(10.667).foregroundStyle(Theme.textMuted).lineLimit(2)
                KeyValueRow("Country", CountryCatalog.country(airport.country)?.name ?? airport.country)
                KeyValueRow("People nearby", Format.people(airport.population))
                KeyValueRow("Runway", "\(Format.number(airport.runwayFt)) ft \(airport.surface == .gravel ? "gravel" : (airport.surface == .water ? "water" : "paved"))")
                if let home, home.code != airport.code { KeyValueRow("From home", Format.km(home.distanceKm(to: airport))) }
                HStack(spacing: 6) {
                    Tag(text: "Level \(required)", color: locked ? Theme.bad : Theme.good)
                    if !world.airline.permits.contains(airport.country) { Tag(text: "Permit needed", color: Theme.gold) }
                }
                Button("Plan a route from here") { onPlan() }.buttonStyle(.smallProminent).disabled(locked)
            }
        }
        .frame(width: 300)
    }
}

/// Shows the stops chosen so far, what is wrong with the route (if anything) and opens it.
struct RoutePlannerPanel: View {
    let session: GameSession
    @Binding var stops: [String]
    let onClose: () -> Void

    var body: some View {
        let world = session.world
        let problem = world.routeProblem(stops: stops)
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("NEW ROUTE").pixelFont(13.333).foregroundStyle(Theme.accent)
                    Spacer()
                    Button("Clear") { stops = [] }.buttonStyle(.small).disabled(stops.isEmpty)
                }
                if stops.isEmpty {
                    Text("Tap airports on the map, in the order you want to fly them.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                } else {
                    Text(Place.list(stops, separator: " > ")).pixelFont(13.333).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    Text("Cycle \(Format.km(cycleKm))" + (stops.count > 2 ? ", back to \(Place.name(stops[0]))" : ", and back")).pixelFont(10.667).foregroundStyle(Theme.textMuted)
                }
                if stops.count >= 2, let problem {
                    Text(Messages.describe(problem)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                    if case .permitRequired(let country, let price) = problem {
                        Button("Buy permit \(Format.compactMoney(price))") { session.perform(sound: .coin) { try $0.buyPermit(country: country) } }.buttonStyle(.small)
                    }
                }
                if stops.count >= 2, problem == nil { ForecastList(session: session, stops: stops) }
                if let notice = session.notice { Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold) }
                HStack(spacing: 8) {
                    Button("Open route") { open() }.buttonStyle(.smallProminent).disabled(stops.count < 2 || problem != nil)
                    Button("Close") { onClose() }.buttonStyle(.small)
                }
            }
        }
        .frame(width: 340)
    }

    private var cycleKm: Double {
        var total = 0.0
        for i in 0..<stops.count {
            guard let a = AirportCatalog.airport(stops[i]), let b = AirportCatalog.airport(stops[(i + 1) % stops.count]) else { continue }
            total += a.distanceKm(to: b)
        }
        return total
    }

    private func open() {
        if session.perform({ _ = try $0.createRoute(stops: stops) }) {
            stops = []
            onClose()
        }
    }
}
