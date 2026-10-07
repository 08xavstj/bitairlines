import SwiftUI
import CoreCatalog
import CoreWorld

/// The world map: pan and zoom, tap airports, plan routes, watch the aircraft fly.
/// What the map remembers between visits (camera, open airport, route being planned) is in MapState, kept by the game shell.
struct MapScreen: View {
    let session: GameSession
    @Bindable var map: MapState
    /// While the guide shows a step, its strip says what to do, so the map's own NEXT line stays out of the way.
    var guideRunning = false
    @State private var dragStart: MapCamera?
    @State private var pinchStart: Double?
    @State private var building: String?
    /// What the player's own aircraft make of the route being planned (RoutePlanCheck.swift), worked out when the stops change.
    @State private var planCheck: PlannerCheck?
    /// Frames of the buttons and panels over the map: no airport name goes under them, and a tap there is not for the map.
    @State private var covered: [CGRect] = []
    /// Frames of the hints over the map (the NEXT line): no airport name goes under them, but taps go through to the map.
    @State private var hints: [CGRect] = []
    /// Size of the map on screen, for framing airports in the part no panel covers.
    @State private var mapSize: CGSize = .zero

    init(session: GameSession, map: MapState, guideRunning: Bool = false) {
        self.session = session
        _map = Bindable(wrappedValue: map)
        self.guideRunning = guideRunning
    }

    var body: some View {
        let world = session.world
        let camera = map.camera
        let important = network(world)
        let legs = world.routes.flatMap { route in route.legs.map { MapLeg(from: $0.from, to: $0.to) } }
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ZStack {
                    // Still while the clock runs: redrawn only when the camera, network, selection or plan changes.
                    MapStillLayer(camera: camera, legs: legs, routePalette: world.airline.branding.primary, home: world.airline.home,
                                  important: important, marked: marked, plan: map.planning ? map.stops : [], planBlocked: map.planning ? planCheck?.blockedLeg : nil,
                                  blocked: covered + hints, cache: map.cache)
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
                        if map.planning {
                            RoutePlannerPanel(session: session, stops: $map.stops, check: planCheck, onClose: { map.stopPlan() })
                                .coversMap()
                        } else if let code = map.selected, let airport = AirportCatalog.airport(code) {
                            AirportPanel(world: world, airport: airport, onPlan: { map.startPlan(from: code) }, onBuild: { building = code }, onClose: { map.selected = nil }, session: session)
                                .coversMap()
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(8)
            }
            .coordinateSpace(.named(MapOverlayFramesKey.space))
            .onPreferenceChange(MapOverlayFramesKey.self) { covered = $0 }
            .onPreferenceChange(MapHintFramesKey.self) { hints = $0 }
            .onChange(of: geo.size, initial: true) { _, size in mapSize = size }
        }
        .background(Theme.background)
        .clipped()
        .sheet(item: Binding(get: { building.map { CodeSheet(id: $0) } }, set: { building = $0?.id })) { sheet in
            BuildSheet(session: session, code: sheet.id)
        }
        // A stopping issue is drawn over the game, under any sheet: close the sheet so the player sees it.
        .onChange(of: session.world.isPausedByIssue) { _, now in if now { building = nil } }
        .onChange(of: planKey, initial: true) { _, _ in planCheck = map.stops.count >= 2 ? session.world.plannerCheck(stops: map.stops) : nil }
        // A job's "Map" button: show both ends beside the panel, not under it.
        .onChange(of: session.mapFocus, initial: true) { _, _ in showAskedFocus() }
        .onChange(of: mapSize) { _, _ in
            showAskedFocus()
            if map.planning && map.stops.count >= 2 { keepInView(map.stops) }
        }
        // While planning, keep every stop in view as stops are added.
        .onChange(of: map.stops) { _, now in if map.planning && now.count >= 2 { keepInView(now) } }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            if !guideRunning && !map.planning { NextStepLine(session: session).hintsOverMap() }
            HStack(spacing: 6) {
                PixelSquareButton(icon: .plus, label: "Zoom in") { zoom(factor: 1.6) }
                PixelSquareButton(icon: .minus, label: "Zoom out") { zoom(factor: 1 / 1.6) }
                Button("Home") { map.goHome(session.world.airline.home) }.buttonStyle(.small)
                Button(map.planning ? "Cancel route" : "New route") {
                    if map.planning { map.stopPlan() } else { map.startPlan(from: nil) }
                }.buttonStyle(map.planning ? AnyButtonStyle(SmallButtonStyle(kind: .danger)) : AnyButtonStyle(SmallButtonStyle(kind: .prominent)))
            }
            .coversMap()
        }
    }

    /// What the planner check depends on: the stops and the fleet (aircraft and their kits).
    private var planKey: String {
        map.stops.joined(separator: ",") + "|" + session.world.aircraft.map { "\($0.typeID)/\($0.kits.count)" }.joined(separator: ",")
    }

    /// Airports drawn in the highlight colour and always named: the stops being planned, the ones another screen asked for, the open one.
    private var marked: Set<String> {
        Set(map.stops + map.focus + (map.selected.map { [$0] } ?? []))
    }

    /// Airports always shown and named: every stop on a route, and home.
    private func network(_ world: World) -> Set<String> {
        Set(world.routes.flatMap { $0.stops } + [world.airline.home])
    }

    /// Frames the airports another screen asked for, with the first one's panel open, then clears the request.
    private func showAskedFocus() {
        guard let codes = session.mapFocus, mapSize != .zero else { return }
        session.mapFocus = nil
        let airports = codes.compactMap { AirportCatalog.airport($0) }
        guard !airports.isEmpty else { return }
        map.stopPlan()
        map.focus = codes
        map.selected = codes.first
        let free = MapFraming.freeRect(size: mapSize, panelShown: true)
        if let framed = MapFraming.camera(showing: airports, size: mapSize, free: free) { map.camera = framed }
    }

    /// Moves the map only when a stop is off screen or under the planner panel.
    private func keepInView(_ codes: [String]) {
        guard mapSize != .zero else { return }
        let airports = codes.compactMap { AirportCatalog.airport($0) }
        let free = MapFraming.freeRect(size: mapSize, panelShown: true)
        if MapFraming.allVisible(airports, camera: map.camera, size: mapSize, free: free) { return }
        if let framed = MapFraming.camera(showing: airports, size: mapSize, free: free, maxPPD: map.camera.ppd) { map.camera = framed }
    }

    // MARK: Gestures

    private func pan(_ value: DragGesture.Value, size: CGSize) {
        if dragStart == nil { dragStart = map.camera }
        guard let start = dragStart else { return }
        let projection = MapProjection(camera: start, size: size)
        let centre = projection.coordinate(at: CGPoint(x: size.width / 2 - value.translation.width, y: size.height / 2 - value.translation.height))
        var camera = map.camera
        camera.lat = centre.lat
        camera.lon = centre.lon
        camera.clamp()
        map.camera = camera
    }

    private func zoom(by magnification: Double) {
        if pinchStart == nil { pinchStart = map.camera.ppd }
        var camera = map.camera
        camera.ppd = (pinchStart ?? camera.ppd) * magnification
        camera.clamp()
        map.camera = camera
    }

    private func zoom(factor: Double) {
        var camera = map.camera
        camera.ppd *= factor
        camera.clamp()
        map.camera = camera
    }

    /// True when a point on the map is under a button or a panel.
    private func isCovered(_ point: CGPoint) -> Bool {
        covered.contains { $0.contains(point) }
    }

    private func tap(at point: CGPoint, size: CGSize, world: World) {
        // A tap that lands between two buttons or on a panel's edge was not meant for the map.
        if isCovered(point) { return }
        let projection = MapProjection(camera: map.camera, size: size)
        let layout = map.cache.airports(projection: projection, important: network(world), selected: marked, blocked: covered + hints)
        var best: (code: String, distance: CGFloat)?
        // Airports under a button or a panel cannot be seen, so a tap never picks one of them.
        for dot in layout.dots where !isCovered(dot.point) {
            let d = hypot(dot.point.x - point.x, dot.point.y - point.y)
            if d < 24, best == nil || d < best!.distance { best = (dot.airport.code, d) }
        }
        guard let code = best?.code else {
            if !map.planning { map.selected = nil; map.focus = [] }
            return
        }
        if map.planning {
            if let i = map.stops.firstIndex(of: code) { map.stops.remove(at: i) } else if map.stops.count < World.maxStops { map.stops.append(code) }
        } else {
            map.selected = map.selected == code ? nil : code
        }
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
            // A busy airport where the airline holds no slot: nothing can leave there until some are bought (the forecast below
            // counts what they cost at its schedule).
            if stops.count >= 2, problem == nil {
                ForEach(world.slotNeeds(stops: stops, frequency: 1).filter(\.noneHeld), id: \.airport) { need in
                    Text("No slots at \(Place.name(need.airport)) yet: no flight can leave there until you buy some in Bases.")
                        .pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                }
            }
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
