import CoreCatalog
import CoreWorld

/// Where a bought aircraft arrives, in words. New and used aircraft are delivered to the headquarters, or to the nearest airport
/// of the network they can use (World.deliveryAirport in FleetActions.swift). The hangar cards can show these lines next to Buy.
enum DeliveryWords {
    /// "Arrives at Whistler: it cannot use Inuvik." when the aircraft is delivered away from home; nil when it arrives at home.
    static func arrival(_ world: World, type: AircraftType) -> String? {
        guard let code = world.deliveryAirport(for: type), code != world.airline.home else { return nil }
        return "Arrives at \(Place.name(code)): it cannot use \(Place.name(world.airline.home))."
    }

    /// Why the aircraft cannot be delivered anywhere, and what to do about it; nil when it can be.
    static func problem(_ world: World, type: AircraftType) -> String? {
        guard world.deliveryProblem(type) != nil else { return nil }
        let home = Place.name(world.airline.home)
        if type.water {
            return "Floatplanes are delivered to your headquarters or the nearest water base you fly to. \(home) has no water: open a route to a lake or seaplane base first."
        }
        let have = AirportCatalog.airport(world.airline.home).map { world.runwayFt(at: $0) } ?? 0
        let kind = type.gravel ? "" : "paved "
        return "New aircraft are delivered to your headquarters at \(home) (\(Format.number(have)) ft) or the nearest airport you fly to that can take them. "
            + "This one needs a \(kind)runway of \(Format.number(type.runwayFt)) ft: fly to a bigger airport first, or move your headquarters on the Airline screen."
    }

    /// The longest runway any aircraft the airline may fly needs (floatplanes left out), in feet.
    static func longestRunwayNeeded(level: Int) -> Int {
        AircraftCatalog.available(atLevel: level).filter { !$0.water }.map(\.runwayFt).max() ?? 0
    }
}
