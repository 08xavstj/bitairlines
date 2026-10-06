// CoreWorld/Hubs.swift: connecting passengers. At a base with a hub terminal, people change planes between the airline's routes:
// someone from A to B rides A to the hub on one route and the hub to B on another, when the airline has no direct A to B and the
// detour is not silly. Worked out once a week; each leg then carries its own market plus these through passengers.
import CoreCatalog
import CoreSim

extension LegState {
    /// Through passengers per day on this leg (changing planes at a hub), before the airline's share of the market.
    public var connectingPaxPerDay: Double {
        get { connectingPaxStore ?? 0 }
        set { connectingPaxStore = newValue == 0 ? nil : newValue }
    }

    /// What each through passenger pays for this leg: their share of the A to B fare, by distance.
    public var connectingFare: Double {
        get { connectingFareStore ?? 0 }
        set { connectingFareStore = newValue == 0 ? nil : newValue }
    }

    /// Average fare per passenger on this leg at a fare multiplier of 1, local and through passengers together.
    public var blendedFare: Double {
        let total = marketPaxPerDay + connectingPaxPerDay
        guard total > 0, connectingPaxPerDay > 0 else { return marketFare }
        return (marketPaxPerDay * marketFare + connectingPaxPerDay * connectingFare) / total
    }
}

extension World {
    /// Airports where passengers can change planes.
    public var hubs: [String] { ops.bases.filter { $0.has(.hubTerminal) }.map(\.airport) }

    /// Recomputes through passengers on every leg.
    mutating func refreshConnections() {
        var pax = [[Double]](repeating: [], count: routes.count)
        var revenue = [[Double]](repeating: [], count: routes.count)
        for r in routes.indices {
            pax[r] = [Double](repeating: 0, count: routes[r].legs.count)
            revenue[r] = [Double](repeating: 0, count: routes[r].legs.count)
        }
        // Pairs the airline already flies directly need no connection.
        var direct = Set<String>()
        for route in routes { for leg in route.legs { direct.insert(leg.from + leg.to) } }

        for hub in hubs {
            guard let h = AirportCatalog.airport(hub) else { continue }
            for r1 in routes.indices {
                for l1 in routes[r1].legs.indices where routes[r1].legs[l1].to == hub {
                    for r2 in routes.indices where r2 != r1 {
                        for l2 in routes[r2].legs.indices where routes[r2].legs[l2].from == hub {
                            let fromCode = routes[r1].legs[l1].from, toCode = routes[r2].legs[l2].to
                            guard fromCode != toCode, !direct.contains(fromCode + toCode),
                                  let a = AirportCatalog.airport(fromCode), let b = AirportCatalog.airport(toCode) else { continue }
                            let ah = a.distanceKm(to: h), hb = h.distanceKm(to: b), ab = a.distanceKm(to: b)
                            guard ab > 50, (ah + hb) / ab <= Tuning.maxConnectionDetour else { continue }
                            let people = Demand.passengersPerDay(from: a, to: b, distanceKm: ab) * Tuning.connectingShare
                            let fare = Fares.market(from: a, to: b, distanceKm: ab) * Tuning.connectingFareDiscount
                            pax[r1][l1] += people
                            revenue[r1][l1] += people * fare * ah / (ah + hb)
                            pax[r2][l2] += people
                            revenue[r2][l2] += people * fare * hb / (ah + hb)
                        }
                    }
                }
            }
        }
        for r in routes.indices {
            for l in routes[r].legs.indices {
                routes[r].legs[l].connectingPaxPerDay = pax[r][l]
                routes[r].legs[l].connectingFare = pax[r][l] > 0 ? revenue[r][l] / pax[r][l] : 0
            }
        }
    }
}
