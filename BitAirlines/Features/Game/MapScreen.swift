import SwiftUI
import CoreCatalog
import CoreWorld

/// The world map: pan and zoom, tap airports, plan routes, watch the aircraft fly.
struct MapScreen: View {
    let session: GameSession
    /// While the guide shows a step, its strip says what to do, so the map's own NEXT line stays out of the way.
    var guideRunning = false
    @State private var camera: MapCamera
    @State private var dragStart: MapCamera?
    @State private var pinchStart: Double?
    @State private var selected: String?
    @State private var planning = false
    @State private var stops: [String] = []
    @State private var building: String?
    /// What the player's own aircraft make of the route being planned (RoutePlanCheck.swift), worked out when the stops change.
    @State private var planCheck: PlannerCheck?
    /// Terrain picture and airport layout, kept between frames.
    @State private var cache = MapCache()
    /// Frames of the buttons and panels over the map (no airport name goes under them).
    @State private var covered: [CGRect] = []
    /// Size of the map on screen, for framing airports in the part no panel covers.
    @State private var mapSize: CGSize = .zero
    /// Airports another screen asked to see (a job's two ends), marked and named until the player moves on.
    @State private var focus: [String] = []

    init(session: GameSession, guideRunning: Bool = false) {
        self.session = session
        self.guideRunning = guideRunning
        let home = AirportCatalog.airport(session.world.airline.home)
        _camera = State(initialValue: MapCamera(lat: home?.latitude ?? 0, lon: home?.longitude ?? 0, ppd: 30))
        #if DEBUG
        if let demoStops = Demo.plannerStops {
            _planning = State(initialValue: true)
            _stops = State(initialValue: demoStops)
        }
        #endif
    }

    var body: some View {
        let world = session.world
        let important = network(world)
        let marked = Set(stops + focus + (selected.map { [$0] } ?? []))
        let legs = world.routes.flatMap { route in route.legs.map { MapLeg(from: $0.from, to: $0.to) } }
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ZStack {
                    // Still while the clock runs: redrawn only when the camera, network, selection or plan changes.
                    MapStillLayer(camera: camera, legs: legs, routePalette: world.airline.branding.primary, home: world.airline.home,
                                  important: important, marked: marked, plan: planning ? stops : [], planBlocked: planning ? planCheck?.blockedLeg : nil,
                                  blocked: covered, cache: cache)
                        .equatable()
                    // Redrawn every tick: only the aircraft.
                    Canvas { context, size in
                        MapRenderer.drawAircraft(&context, world: world, projection: MapProjection(camera: camera, size: size))
                    }
                }
                .contentShape(Rectangle())
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
                    // Clear of the toolbar along the top.
                    Spacer(minLength: MapFraming.toolbarReserve)
                    HStack(alignment: .bottom, spacing: 8) {
                        if planning {
                            RoutePlannerPanel(session: session, stops: $stops, check: planCheck, onClose: { planning = false; stops = [] })
                                .coversMap()
                        } else if let code = selected, let airport = AirportCatalog.airport(code) {
                            AirportPanel(world: world, airport: airport, onPlan: { startPlan(from: code) }, onBuild: { building = code }, onClose: { selected = nil }, session: session)
                                .coversMap()
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(8)
            }
            .coordinateSpace(.named(MapOverlayFramesKey.space))
            .onPreferenceChange(MapOverlayFramesKey.self) { covered = $0 }
            .onChange(of: geo.size, initial: true) { _, size in mapSize = size }
        }
        .background(Theme.background)
        .clipped()
        .sheet(item: Binding(get: { building.map { CodeSheet(id: $0) } }, set: { building = $0?.id })) { sheet in
            BuildSheet(session: session, code: sheet.id)
        }
        // A stopping issue is drawn over the game, under any sheet: close the sheet so the player sees it.
        .onChange(of: session.world.isPausedByIssue) { _, now in if now { building = nil } }
        .onChange(of: planKey, initial: true) { _, _ in planCheck = stops.count >= 2 ? session.world.plannerCheck(stops: stops) : nil }
        // A job's "Map" button: show both ends beside the panel, not under it.
        .onChange(of: session.mapFocus, initial: true) { _, _ in showAskedFocus() }
        .onChange(of: mapSize) { _, _ in
            showAskedFocus()
            if planning && stops.count >= 2 { keepInView(stops) }
        }
        // While planning, keep every stop in view as stops are added.
        .onChange(of: stops) { _, now in if planning && now.count >= 2 { keepInView(now) } }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            if !guideRunning && !planning { NextStepLine(session: session) }
            PixelSquareButton(icon: .plus, label: "Zoom in") { zoom(factor: 1.6) }
            PixelSquareButton(icon: .minus, label: "Zoom out") { zoom(factor: 1 / 1.6) }
            Button("Home") { goHome() }.buttonStyle(.small)
            Button(planning ? "Cancel route" : "New route") {
                if planning { planning = false; stops = [] } else { startPlan(from: nil) }
            }.buttonStyle(planning ? AnyButtonStyle(SmallButtonStyle(kind: .danger)) : AnyButtonStyle(SmallButtonStyle(kind: .prominent)))
        }
        .coversMap()
    }

    /// What the planner check depends on: the stops and the fleet (aircraft and their kits).
    private var planKey: String {
        stops.joined(separator: ",") + "|" + session.world.aircraft.map { "\($0.typeID)/\($0.kits.count)" }.joined(separator: ",")
    }

    /// Airports always shown and named: every stop on a route, and home.
    private func network(_ world: World) -> Set<String> {
        Set(world.routes.flatMap { $0.stops } + [world.airline.home])
    }

    private func goHome() {
        guard let home = AirportCatalog.airport(session.world.airline.home) else { return }
        focus = []
        camera = MapCamera(lat: home.latitude, lon: home.longitude, ppd: 30)
    }

    private func startPlan(from code: String?) {
        planning = true
        stops = code.map { [$0] } ?? []
        selected = nil
        focus = []
    }

    /// Frames the airports another screen asked for, with the first one's panel open, then clears the request.
    private func showAskedFocus() {
        guard let codes = session.mapFocus, mapSize != .zero else { return }
        session.mapFocus = nil
        let airports = codes.compactMap { AirportCatalog.airport($0) }
        guard !airports.isEmpty else { return }
        planning = false
        stops = []
        focus = codes
        selected = codes.first
        let free = MapFraming.freeRect(size: mapSize, panelShown: true)
        if let framed = MapFraming.camera(showing: airports, size: mapSize, free: free) { camera = framed }
    }

    /// Moves the map only when a stop is off screen or under the planner panel.
    private func keepInView(_ codes: [String]) {
        guard mapSize != .zero else { return }
        let airports = codes.compactMap { AirportCatalog.airport($0) }
        let free = MapFraming.freeRect(size: mapSize, panelShown: true)
        if MapFraming.allVisible(airports, camera: camera, size: mapSize, free: free) { return }
        if let framed = MapFraming.camera(showing: airports, size: mapSize, free: free, maxPPD: camera.ppd) { camera = framed }
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
        let marked = Set(stops + focus + (selected.map { [$0] } ?? []))
        let layout = cache.airports(projection: projection, important: network(world), selected: marked, blocked: covered)
        var best: (code: String, distance: CGFloat)?
        for dot in layout.dots {
            let d = hypot(dot.point.x - point.x, dot.point.y - point.y)
            if d < 24, best == nil || d < best!.distance { best = (dot.airport.code, d) }
        }
        guard let code = best?.code else {
            if !planning { selected = nil; focus = [] }
            return
        }
        if planning {
            if let i = stops.firstIndex(of: code) { stops.remove(at: i) } else if stops.count < World.maxStops { stops.append(code) }
        } else {
            selected = selected == code ? nil : code
        }
    }
}

/// Facts about the airport the player tapped.
struct AirportPanel: View {
    let world: World
    let airport: Airport
    let onPlan: () -> Void
    let onBuild: () -> Void
    let onClose: () -> Void
    /// For the Leave button (GrowthSheets.swift); nil hides it.
    var session: GameSession? = nil

    var body: some View {
        let required = Progression.requiredLevel(for: airport)
        let locked = required > world.airline.level && airport.code != world.airline.home
        let home = AirportCatalog.airport(world.airline.home)
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(airport.label.uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    PixelSquareButton(icon: .close, label: "Close", action: onClose)
                }
                Text(airport.name).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                KeyValueRow("Country", CountryCatalog.country(airport.country)?.name ?? airport.country)
                KeyValueRow("People nearby", Format.people(airport.population))
                KeyValueRow("Runway", "\(Format.number(world.runwayFt(at: airport))) ft \(world.surface(at: airport) == .gravel ? "gravel" : (world.surface(at: airport) == .water ? "water" : "paved"))")
                if airport.surface != .water && !world.isLit(airport) && world.ops.mode.daylightLimits { KeyValueRow("Lights", "None: daylight only", color: Theme.gold) }
                if world.ops.mode.fuelOnlyWhereSold { KeyValueRow("Fuel", world.sellsFuel(airport) ? "Sold here" : "None", color: world.sellsFuel(airport) ? Theme.good : Theme.gold) }
                if world.isFrozen(airport, month: world.clock.date.month) { KeyValueRow("Lake", "Frozen: skis only", color: Theme.info) }
                if world.needsSlots(airport) { KeyValueRow("Slots", "\(world.slotsHeld(at: airport.code)) held, \(world.slotsScheduled(at: airport.code)) used") }
                if let base = world.ops.bases.first(where: { $0.airport == airport.code }) {
                    Text("Your base: " + base.facilities.map { Words.name($0) }.joined(separator: ", ")).pixelFont(10.667).foregroundStyle(Theme.good).fixedSize(horizontal: false, vertical: true)
                }
                if let home, home.code != airport.code { KeyValueRow("From home", Format.km(home.distanceKm(to: airport))) }
                HStack(spacing: 6) {
                    Tag(text: "Level \(required)", color: locked ? Theme.bad : Theme.good)
                    if !world.airline.permits.contains(airport.country) { Tag(text: "Permit needed", color: Theme.gold) }
                }
                HStack(spacing: 8) {
                    Button("Plan a route") { onPlan() }.buttonStyle(.smallProminent).disabled(locked)
                    Button("Build here") { onBuild() }.buttonStyle(.small).disabled(locked)
                }
                if let session, world.leaveAirportProblem(code: airport.code) == nil { LeaveAirportButton(session: session, code: airport.code) }
            }
        }
        .frame(width: 340)
    }
}

/// Shows the stops chosen so far, what is wrong with the route (if anything) and opens it.
struct RoutePlannerPanel: View {
    let session: GameSession
    @Binding var stops: [String]
    var check: PlannerCheck? = nil
    let onClose: () -> Void

    var body: some View {
        let problem = session.world.routeProblem(stops: stops)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                // The buttons sit at the top, so a long list of notes below never pushes them off the screen.
                HStack(spacing: 8) {
                    Text("NEW ROUTE").pixelFont(13.333).foregroundStyle(Theme.accent).lineLimit(1).fixedSize()
                    Spacer(minLength: 4)
                    Button("Open route") { open() }.buttonStyle(.smallProminent).disabled(stops.count < 2 || problem != nil)
                    Button("Close") { onClose() }.buttonStyle(.small)
                }
                ViewThatFits(in: .vertical) {
                    details(problem: problem)
                    ScrollView { details(problem: problem) }
                }
            }
        }
        .frame(width: 340)
    }

    @ViewBuilder private func details(problem: WorldError?) -> some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 6) {
            if stops.isEmpty {
                Text("Tap airports on the map, in the order you want to fly them.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Text(Place.list(stops, separator: " > ")).pixelFont(13.333).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Clear") { stops = [] }.buttonStyle(.small)
                }
                Text("Cycle \(Format.km(cycleKm))" + (stops.count > 2 ? ", back to \(Place.name(stops[0]))" : ", and back")).pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }
            if stops.count >= 2, let problem {
                Text(Messages.describe(problem, cash: world.airline.cash)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                if case .permitRequired(let country, let price) = problem {
                    Button("Buy permit \(Format.compactMoney(price))") { session.perform(sound: .coin) { try $0.buyPermit(country: country) } }.buttonStyle(.small)
                }
            }
            if let notice = session.notice { Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true) }
            if stops.count >= 2, let check { PlannerFleetNote(world: world, stops: $stops, check: check) }
            if stops.count >= 2, problem == nil { ForecastList(session: session, stops: stops) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
