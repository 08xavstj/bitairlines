import Foundation
import CoreCatalog
@testable import CoreWorld

enum Fixtures {
    static func world(seed: UInt64 = 7, home: String = "YEV", type: String = "c208", difficulty: Difficulty = .standard) throws -> World {
        try World.newGame(NewGameConfig(airlineName: "Lontra Air", airlineCode: "LT", homeAirport: home, branding: .starter,
                                        difficulty: difficulty, starterTypeID: type, seed: seed))
    }

    /// A Caravan on Inuvik - Tuktoyaktuk, two departures a day each way.
    static func flyingWorld(seed: UInt64 = 7, frequency: Double = 2) throws -> World {
        var w = try world(seed: seed)
        let route = try w.createRoute(stops: ["YEV", "YUB"])
        try w.assign(aircraftID: w.aircraft[0].id, toRoute: route)
        try w.setFrequency(routeID: route, perDay: frequency)
        return w
    }

    static func encode(_ w: World) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(w)
    }

    /// Steps the world until the first aircraft is waiting at the gate (so a test can break it down realistically).
    static func advanceUntilBoarding(_ w: inout World) {
        for _ in 0..<2000 {
            if case .boarding = w.aircraft[0].status { return }
            w.advance(byMinutes: 5)
        }
    }
}
