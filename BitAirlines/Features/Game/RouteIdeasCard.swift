import SwiftUI
import CoreCatalog
import CoreWorld

/// Remembers the suggested routes, so they are not worked out again on every clock tick. They are worked out again when the
/// network, the fleet's types, the hangar, the permits, the level or the focus change, and otherwise once a game week.
@MainActor
final class RouteIdeasCache {
    static let shared = RouteIdeasCache()

    /// What the suggestions depend on.
    struct Key: Hashable {
        var home: String
        var routes: [String]
        var bases: [String]
        var types: [String]
        var level: Int
        var permits: [String]
        var week: Int
        var focus: RouteIdeaFocus
        /// Bigger-city ideas are also judged for types on sale in the hangar.
        var listings: [String]
    }

    private var key: Key?
    private var ideas: [RouteIdea] = []

    func ideas(world: World, focus: RouteIdeaFocus) -> [RouteIdea] {
        let key = Key(home: world.airline.home,
                      routes: world.routes.map { $0.stops.joined(separator: "-") }.sorted(),
                      bases: world.ops.bases.map { $0.airport }.sorted(),
                      types: world.aircraft.map { $0.isDelivered ? $0.typeID : $0.typeID + " on order" }.sorted(),
                      level: world.airline.level,
                      permits: world.airline.permits.sorted(),
                      week: world.clock.dayIndex / 7,
                      focus: focus,
                      listings: focus == .biggerCities ? world.market.listings.map { $0.typeID }.sorted() : [])
        if key == self.key { return ideas }
        ideas = world.routeIdeas(limit: 5, focus: focus)
        self.key = key
        return ideas
    }
}

/// The words for a suggested route.
enum RouteIdeaWords {
    /// "Inuvik to Tuktoyaktuk"
    static func route(_ idea: RouteIdea) -> String {
        "\(Place.name(idea.stops.first ?? "")) to \(Place.name(idea.stops.last ?? ""))"
    }

    /// "About +$1,200 a day with a Cessna 208B Grand Caravan EX." For a type the airline does not have: "... with a DHC-6 Twin Otter you could buy."
    static func profit(_ idea: RouteIdea) -> String {
        let name = AircraftCatalog.type(idea.typeID)?.displayName ?? idea.typeID
        let buy = idea.typeOwned ? "" : " you could buy"
        return "About \(Format.perDay(idea.profitPerDay)) with \(GrowthWords.article(name)) \(name)\(buy)."
    }

    /// The distance and why the route is worth a look.
    static func reason(_ idea: RouteIdea) -> String {
        let why: String
        switch idea.reason {
        case .noRoadTown: why = "\(Place.name(idea.place)) has no road."
        case .bigMarket: why = "About \(Int(idea.passengersPerDay.rounded())) people a day would fly it."
        case .extendsNetwork: why = "Adds \(Place.name(idea.place)) to your network."
        case .linksNetwork: why = "Links two airports you already fly to."
        }
        return "\(Format.km(idea.distanceKm)). " + why
    }
}

/// At the top of Routes: the best routes the airline could open now with the aircraft it has.
struct RouteIdeasCard: View {
    let session: GameSession
    /// Called with the id of a route opened without an aircraft, so the screen can show it (Routes opens its sheet).
    let onOpened: ((Int) -> Void)?
    /// Hide is kept per game slot, so the card does not open again on every visit.
    @AppStorage private var hidden: Bool
    /// The focus picked for this game slot ("" until the player picks one: then it follows the level).
    @AppStorage private var focusChoice: String

    init(session: GameSession, onOpened: ((Int) -> Void)? = nil) {
        self.session = session
        self.onOpened = onOpened
        _hidden = AppStorage(wrappedValue: false, "routeIdeasHidden.\(session.slot)")
        _focusChoice = AppStorage(wrappedValue: "", "routeIdeasFocus.\(session.slot)")
    }

    /// Small strips at the start; bigger cities from certificate level 2, unless the player picked.
    private var focus: RouteIdeaFocus {
        RouteIdeaFocus(rawValue: focusChoice) ?? (session.world.airline.level >= 2 ? .biggerCities : .smallStrips)
    }

    var body: some View {
        let focus = self.focus
        let ideas = RouteIdeasCache.shared.ideas(world: session.world, focus: focus)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Suggested routes").pixelFont(16).foregroundStyle(Theme.accent).lineLimit(1)
                    Spacer()
                    Button(hidden ? "Show" : "Hide") { hidden.toggle() }.buttonStyle(.small)
                }
                if !hidden {
                    PixelChoice(options: [(label: "Small strips", value: RouteIdeaFocus.smallStrips), (label: "Bigger cities", value: RouteIdeaFocus.biggerCities)],
                                selection: Binding(get: { focus }, set: { focusChoice = $0.rawValue }))
                    if ideas.isEmpty {
                        Text(focus == .biggerCities
                             ? "No bigger town within reach would make money yet. A higher certificate level opens busier airports."
                             : "No new route nearby would make money with the aircraft you have now.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Profit is for one aircraft, once people know the route.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(ideas) { idea in RouteIdeaRow(session: session, idea: idea, onOpened: onOpened) }
                }
            }
        }
    }
}

/// One suggestion, with buttons to open it (and to put a parked aircraft on it).
struct RouteIdeaRow: View {
    let session: GameSession
    let idea: RouteIdea
    var onOpened: ((Int) -> Void)? = nil

    var body: some View {
        let planeID = session.world.idleAircraftID(for: idea)
        let registration = planeID.flatMap { id in session.world.aircraft.first { $0.id == id }?.registration }
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(RouteIdeaWords.route(idea)).pixelFont(13.333).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(RouteIdeaWords.profit(idea)).pixelFont(10.667).foregroundStyle(Theme.good).fixedSize(horizontal: false, vertical: true)
                Text(RouteIdeaWords.reason(idea)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if !idea.typeOwned {
                    Text(GrowthWords.buyHint(idea.typeID)).pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if let planeID {
                    Button("Open with \(registration ?? "a parked aircraft")") { openAndAssign(planeID) }.buttonStyle(.smallProminent)
                }
                Button(planeID == nil ? "Open route" : "Open route only") { open() }.buttonStyle(.small)
            }
        }
        .padding(.top, 6)
    }

    /// Opens the route without an aircraft. The opened pair leaves the list at once, so say where it went.
    private func open() {
        var opened: Int?
        guard session.perform(sound: .coin, { opened = try $0.createRoute(stops: idea.stops) }), let routeID = opened else { return }
        if let onOpened {
            onOpened(routeID)
        } else {
            session.notice = "Opened \(RouteIdeaWords.route(idea)). It has no aircraft yet: give it one under Routes."
        }
    }

    /// Opens the route and assigns the aircraft together: if the aircraft is refused, the route is not opened either.
    private func openAndAssign(_ planeID: Int) {
        let opened = session.perform(sound: .coin) { (world: inout World) in
            var copy = world
            let routeID = try copy.createRoute(stops: idea.stops)
            try copy.assign(aircraftID: planeID, toRoute: routeID)
            world = copy
        }
        guard opened else { return }
        let registration = session.world.aircraft.first { $0.id == planeID }?.registration ?? "Your aircraft"
        session.notice = "Opened \(RouteIdeaWords.route(idea)). \(registration) flies it on its own from now on."
    }
}
