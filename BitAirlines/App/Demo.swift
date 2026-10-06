#if DEBUG
import Foundation
import CoreCatalog
import CoreWorld

/// Developer shortcuts for screenshots: launch the app with `-SkipSplash -DemoScreen map` (or fleet, routes, market, money, inbox, airline, issue, title, new0 to new4).
/// Only in Debug builds; CI uses it to take pictures of every screen (tools/ci_screenshots.sh).
enum Demo {
    static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static var skipSplash: Bool { CommandLine.arguments.contains("-SkipSplash") }
    static var screen: String? { value(after: "-DemoScreen") }

    static var branding: Branding {
        var b = Branding(primary: 17, secondary: 11, accent: 6, style: .belly, logo: Branding.blankLogo())
        b.logo = LogoTemplates.all[3].logo(for: b)
        return b
    }

    /// A brand new airline for the guide: stage 1 has nothing, 2 has a route, 3 has the aircraft assigned to it.
    static func freshWorld(stage: Int) throws -> World {
        var w = try World.newGame(NewGameConfig(airlineName: "Aurora Air", airlineCode: "AU", homeAirport: "YEV", branding: branding,
                                                difficulty: .easy, starterTypeID: "c208", seed: 42))
        if stage >= 2 { try w.createRoute(stops: ["YEV", "YUB"]) }
        if stage >= 3, let route = w.routes.first { try w.assign(aircraftID: w.aircraft[0].id, toRoute: route.id) }
        return w
    }

    /// The map opens with these stops already chosen, to show the route planner.
    static var plannerStops: [String]? { screen == "planner" ? ["YEV", "YUB", "YSY"] : nil }

    /// An airline a few weeks in: two aircraft, two routes, some money earned.
    static func world(issue: Bool) throws -> World {
        var w = try World.newGame(NewGameConfig(airlineName: "Aurora Air", airlineCode: "AU", homeAirport: "YEV", branding: branding,
                                                difficulty: .easy, starterTypeID: "c208", seed: 42))
        let milkRun = try w.createRoute(stops: ["YEV", "YUB", "YSY"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: milkRun)
        if let listing = w.market.listings.first(where: { (AircraftCatalog.type($0.typeID).map { $0.level <= 1 && w.homeProblem($0) == nil } ?? false) && AircraftCatalog.type($0.typeID)?.canLand(at: AirportCatalog.airport("YZF") ?? AirportCatalog.all[0]) == true && $0.price < w.airline.cash }) {
            let id = try w.buyUsed(listingID: listing.id)
            w.advance(byMinutes: 12 * 1440)
            let long = try w.createRoute(stops: ["YEV", "YZF"])
            try? w.assign(aircraftID: id, toRoute: long)
        }
        // Show off the added systems: a base with a depot and a hangar, premium service, fuel bought ahead, an event.
        try? w.build(.fuelDepot, at: "YEV")
        try? w.build(.hangar, at: "YEV")
        try? w.setService(routeID: milkRun, level: .premium)
        try? w.buyFuel(kg: 10_000)
        w.startEvent(.earlyThaw, at: "YUB")
        w.advance(byMinutes: 30 * 1440)
        if screen == "perks" { w.ops.perkChoices = [.quickTurns, .homeFuelDeal, .knownFace] }
        if issue {
            w.airline.cash = -250_000
            w.advance(byMinutes: 2 * 1440)
        }
        return w
    }
}
#endif
