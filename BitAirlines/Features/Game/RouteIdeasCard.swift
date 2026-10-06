import SwiftUI
import CoreCatalog
import CoreWorld

/// Remembers the suggested routes, so they are not worked out again on every clock tick. They are worked out again when the
/// network, the fleet's types, the permits or the level change, and otherwise once a game day.
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
        var day: Int
    }

    private var key: Key?
    private var ideas: [RouteIdea] = []

    func ideas(world: World) -> [RouteIdea] {
        let key = Key(home: world.airline.home,
                      routes: world.routes.map { $0.stops.joined(separator: "-") }.sorted(),
                      bases: world.ops.bases.map { $0.airport }.sorted(),
                      types: world.aircraft.map { $0.isDelivered ? $0.typeID : $0.typeID + " on order" }.sorted(),
                      level: world.airline.level,
                      permits: world.airline.permits.sorted(),
                      day: world.clock.dayIndex)
        if key == self.key { return ideas }
        ideas = world.routeIdeas(limit: 5)
        self.key = key
        return ideas
    }
}

/// The words for a suggested route.
enum RouteIdeaWords {
    /// "Inuvik to Tuktoyaktuk: about +$1,200 a day with a Cessna 208B Grand Caravan EX."
    static func headline(_ idea: RouteIdea) -> String {
        let from = Place.name(idea.stops.first ?? "")
        let to = Place.name(idea.stops.last ?? "")
        let name = AircraftCatalog.type(idea.typeID)?.displayName ?? idea.typeID
        let startsWithVowel = name.first.map { "AEIOU".contains($0) } ?? false
        let article = startsWithVowel ? "an" : "a"
        return "\(from) to \(to): about \(Format.perDay(idea.profitPerDay)) with \(article) \(name)."
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
    @State private var open = true

    var body: some View {
        let ideas = RouteIdeasCache.shared.ideas(world: session.world)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Suggested routes").pixelFont(16).foregroundStyle(Theme.accent).lineLimit(1)
                    Spacer()
                    Button(open ? "Hide" : "Show") { open.toggle() }.buttonStyle(.small)
                }
                if open {
                    if ideas.isEmpty {
                        Text("No new route nearby would make money with the aircraft you have now.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Profit is for one aircraft, once people know the route.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(ideas) { idea in RouteIdeaRow(session: session, idea: idea) }
                }
            }
        }
    }
}

/// One suggestion, with buttons to open it (and to put a parked aircraft on it).
struct RouteIdeaRow: View {
    let session: GameSession
    let idea: RouteIdea

    var body: some View {
        let planeID = session.world.idleAircraftID(for: idea)
        VStack(alignment: .leading, spacing: 4) {
            Text(RouteIdeaWords.headline(idea)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Text(RouteIdeaWords.reason(idea)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open route") { open() }.buttonStyle(.small)
                if let planeID {
                    Button("Open and assign") { openAndAssign(planeID) }.buttonStyle(.smallProminent)
                }
            }
        }
        .padding(.top, 4)
    }

    private func open() {
        session.perform(sound: .coin) { _ = try $0.createRoute(stops: idea.stops) }
    }

    /// Opens the route and assigns the aircraft together: if the aircraft is refused, the route is not opened either.
    private func openAndAssign(_ planeID: Int) {
        session.perform(sound: .coin) { (world: inout World) in
            var copy = world
            let routeID = try copy.createRoute(stops: idea.stops)
            try copy.assign(aircraftID: planeID, toRoute: routeID)
            world = copy
        }
    }
}
