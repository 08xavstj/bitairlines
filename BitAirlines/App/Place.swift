import CoreCatalog

/// How the game names a place: the city or town, never the airport code.
enum Place {
    static func name(_ code: String) -> String { AirportCatalog.airport(code)?.label ?? code }

    static func list(_ codes: [String], separator: String = " - ") -> String { codes.map { name($0) }.joined(separator: separator) }
}
