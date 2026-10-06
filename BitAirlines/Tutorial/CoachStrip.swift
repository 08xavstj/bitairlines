import SwiftUI
import CoreWorld

/// A strip under the top bar that tells a new player what to do next, and lights up the button to press. Gone once the guide is finished.
struct CoachStrip: View {
    let session: GameSession
    let coach: TutorialCoach
    @Environment(\.pixelStep) private var pixelStep
    @State private var suggestion: (code: String, perDay: Double)?
    /// The suggested route has been shown on the map once (the player may pan away after that).
    @State private var framed = false
    /// Skip guide was pressed: the strip asks before ending the guide for good.
    @State private var confirmingSkip = false

    var body: some View {
        if coach.active {
            // The guide follows the world: it looks at the step the world is on and tells the coach when that changes.
            // The stack is always there (even before the first step is known), so the change handler is installed.
            let wanted = Tutorial.step(world: session.world, speed: session.speed, seen: coach.seen, jobsEarly: coach.jobsEarly)
            VStack(spacing: 0) { strip }
                // A strip under the top bar: the largest text sizes would make it taller than the screen, so it stops one step up.
                .environment(\.pixelStep, min(pixelStep, 1))
                .onChange(of: wanted, initial: true) { _, _ in coach.update(world: session.world, speed: session.speed) }
                .onChange(of: coach.step) { old, new in stepChanged(from: old, to: new) }
                .task {
                    suggestion = Tutorial.suggestion(world: session.world)
                    // Where the first routes pay little, jobs are taught right after the routes tip.
                    coach.jobsEarly = Tutorial.routesAreThin(suggestion)
                    coach.update(world: session.world, speed: session.speed)
                    frameSuggestion()
                }
        }
    }

    @ViewBuilder private var strip: some View {
        if let step = coach.step {
            HStack(alignment: .center, spacing: 10) {
                // Skip sits at the far end from Next, so a slightly-off tap on Next never ends the guide.
                VStack(alignment: .leading, spacing: 6) {
                    Tag(text: "Step \(step.rawValue + 1) of \(TutorialStep.allCases.count)", color: Theme.gold)
                    if !confirmingSkip { Button("Skip guide") { confirmingSkip = true }.buttonStyle(.small) }
                }
                if confirmingSkip {
                    message("Skip the guide? It does not come back for this airline.")
                    Spacer(minLength: 4)
                    Button("Keep guide") { confirmingSkip = false }.buttonStyle(.small)
                    Button("Skip it") {
                        confirmingSkip = false
                        coach.finish()
                    }.buttonStyle(.smallDanger)
                } else {
                    message(Tutorial.text(for: step, world: session.world, suggestion: suggestion, flights: session.world.airline.stats.flights))
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 6) { actions(step) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surfaceRaised)
            .overlay(alignment: .top) { Rectangle().fill(Theme.gold).frame(height: 2) }
            .accessibilityElement(children: .contain)
        } else {
            // A real (if empty) view, so the handlers above it run before the first step is known.
            Color.clear.frame(height: 0)
        }
    }

    /// The step's words: a few lines at most, scrolling when a long tip does not fit.
    private func message(_ text: String) -> some View {
        let line = Text(text).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        return ViewThatFits(in: .vertical) {
            line
            ScrollView { line.frame(maxWidth: .infinity, alignment: .leading) }
        }
        .frame(maxHeight: 76)
    }

    @ViewBuilder private func actions(_ step: TutorialStep) -> some View {
        // Step 1 in one tap: the suggested route, opened with the parked aircraft on it (the manual way stays in the words).
        if step == .openRoute, let suggestion, let plane = parkedAircraft,
           session.world.routeProblem(stops: [session.world.airline.home, suggestion.code]) == nil {
            Button("Open it with \(plane.registration)") { openSuggested(suggestion.code, planeID: plane.id) }.buttonStyle(.smallProminent)
        }
        if step.needsNext {
            Button(step == TutorialStep.tour.last ? "Done" : "Next") { coach.next(world: session.world, speed: session.speed) }.buttonStyle(.smallProminent)
        } else if step.canPutOff {
            Button("Later") { coach.next(world: session.world, speed: session.speed) }.buttonStyle(.small)
        }
    }

    /// A delivered aircraft with nothing to do: the one the one-tap button puts on the suggested route.
    private var parkedAircraft: Aircraft? {
        session.world.aircraft.first { plane in
            guard plane.isDelivered, plane.routeID == nil, plane.jobID == nil, case .idle = plane.status else { return false }
            return true
        }
    }

    /// Opens home to the suggested airport and assigns the aircraft together: if the aircraft is refused, the route is not opened either.
    private func openSuggested(_ code: String, planeID: Int) {
        let stops = [session.world.airline.home, code]
        session.perform(sound: .coin) { (world: inout World) in
            var copy = world
            let routeID = try copy.createRoute(stops: stops)
            try copy.assign(aircraftID: planeID, toRoute: routeID)
            world = copy
        }
    }

    private func stepChanged(from old: TutorialStep?, to new: TutorialStep?) {
        // The first payoff: the flights the player watched are done.
        if new == .review && (old == .watch || old == .startClock) { session.audio?.play(.coin) }
        if new == .openRoute { frameSuggestion() }
    }

    /// While step 1 names an airport, the map shows it: home and the suggestion are framed clear of the panels and named
    /// (MapScreen answers session.mapFocus). Once per strip, so the player can pan away.
    private func frameSuggestion() {
        guard !framed, coach.step == .openRoute, let suggestion else { return }
        framed = true
        session.mapFocus = [session.world.airline.home, suggestion.code]
    }
}

extension View {
    /// A gold outline round the control the guide wants pressed next.
    func coachOutline(_ lit: Bool) -> some View {
        overlay { if lit { PixelShape(step: 2).inset(by: 1).stroke(Theme.gold, lineWidth: 3).allowsHitTesting(false) } }
    }
}
