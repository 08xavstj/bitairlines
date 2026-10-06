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

/// One way through a hub: leg l1 of route r1 into the hub, then leg l2 of route r2 out of it.
struct ConnectionPath {
    var from: String
    var to: String
    var r1: Int
    var l1: Int
    var r2: Int
    var l2: Int
    /// Share of the trip's distance (and so of its fare) flown on the leg into the hub.
    var inboundShare: Double
    /// How often this path flies; a pair's people are split across its paths by this.
    var weight: Double

    var pairKey: String { from + ":" + to }
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

        // Every way the airline could carry someone from A to B through a hub. Overlapping routes give several ways for one pair.
        var paths: [ConnectionPath] = []
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
                            let weight = max(0.01, min(routes[r1].frequency, routes[r2].frequency))
                            paths.append(ConnectionPath(from: fromCode, to: toCode, r1: r1, l1: l1, r2: r2, l2: l2,
                                                        inboundShare: ah / (ah + hb), weight: weight))
                        }
                    }
                }
            }
        }
        // Each pair's people are counted once and split across its paths by how often each path flies.
        var pairs: [String] = []
        for path in paths where !pairs.contains(path.pairKey) { pairs.append(path.pairKey) }
        for key in pairs.sorted() {
            let options = paths.filter { $0.pairKey == key }
            guard let first = options.first, let a = AirportCatalog.airport(first.from), let b = AirportCatalog.airport(first.to) else { continue }
            let ab = a.distanceKm(to: b)
            let people = Demand.passengersPerDay(from: a, to: b, distanceKm: ab) * Tuning.connectingShare
            let fare = Fares.market(from: a, to: b, distanceKm: ab) * Tuning.connectingFareDiscount
            let totalWeight = options.reduce(0.0) { $0 + $1.weight }
            for path in options {
                let part = people * path.weight / totalWeight
                pax[path.r1][path.l1] += part
                revenue[path.r1][path.l1] += part * fare * path.inboundShare
                pax[path.r2][path.l2] += part
                revenue[path.r2][path.l2] += part * fare * (1 - path.inboundShare)
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
