// CoreWorld/Jobs.swift: the job board. One-off work at airports near the network (a medevac, a mail run, fuel drums, a crew change,
// a fishing lodge charter, a survey, a load of freight), each with a deadline and a price. Taken jobs are flown in JobFlights.swift.
import CoreCatalog
import CoreSim

public enum JobKind: String, Sendable, Hashable, Codable, CaseIterable {
    case medevac, mail, fuelDrums, crewChange, lodgeCharter, survey, freight
    /// Special jobs that only come with events.
    case evacuation, filmCrew

    /// Pay as a multiple of what the same load would earn at the going fare or freight rate.
    var payFactor: Double {
        switch self {
        case .medevac: 4.0
        case .mail: 2.2
        case .fuelDrums: 1.8
        case .crewChange: 2.2
        case .lodgeCharter: 2.6
        case .survey: 2.4
        case .freight: 1.4
        case .evacuation: 3.0
        case .filmCrew: 3.5
        }
    }
}

public struct Job: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var kind: JobKind
    public var from: String
    public var to: String
    public var passengers: Int
    public var cargoKg: Int
    /// Paid on landing at `to`; half if late.
    public var pay: Int
    /// Land by this minute for full pay.
    public var deadlineMinute: Int
    /// The offer goes if nobody takes it by this minute.
    public var expiresMinute: Int
    /// The aircraft flying it, once taken.
    public var aircraftID: Int?
    /// True once the load is on board (on the way to `to`).
    public var loaded: Bool
    /// The real day this job is the daily dispatch for (DailyDispatch.swift); nil for other jobs and in older saves.
    public var dispatchDay: Int? = nil
    /// The seasonal event this job belongs to (SeasonalEvents.swift); nil for other jobs and in older saves.
    public var season: SeasonKind? = nil

    public var isTaken: Bool { aircraftID != nil }
    /// A dispatch or seasonal job: it stays on the board while its real day or event lasts, not by game time.
    public var isSpecial: Bool { dispatchDay != nil || season != nil }
}

extension World {
    /// How many offers the board holds at once.
    var jobBoardSize: Int { 6 + 2 * airline.level }

    /// The airports jobs come from: the home, every stop the airline flies to and its bases.
    var servedAirports: [String] {
        Array(Set([airline.home] + routes.flatMap { $0.stops } + ops.bases.map(\.airport))).sorted()
    }

    /// Recomputes the airports within reach of the network (where jobs and events happen) when the network has changed.
    mutating func refreshJobArea() {
        let key = servedAirports.joined(separator: ",") + "|\(airline.level)|\(airline.permits.sorted().joined())"
        guard key != ops.jobAreaKey else { return }
        let served = servedAirports.compactMap { AirportCatalog.airport($0) }
        let reachDegrees = Tuning.jobAreaKm / 111.0
        var area: [String] = []
        for airport in AirportCatalog.all where airline.permits.contains(airport.country) {
            // Cheap latitude test first; the great-circle distance only for airports that pass it.
            let near = served.contains { s in
                let dLat = s.latitude - airport.latitude
                return dLat <= reachDegrees && dLat >= -reachDegrees && s.distanceKm(to: airport) <= Tuning.jobAreaKm
            }
            guard near else { continue }
            if Progression.requiredLevel(for: airport) <= airline.level || airport.code == airline.home { area.append(airport.code) }
        }
        ops.jobArea = area.sorted()
        ops.jobAreaKey = key
    }

    /// Once a day: old offers go, new ones come.
    mutating func dailyJobs() {
        let now = clock.minute
        ops.jobs.removeAll { !$0.isTaken && $0.expiresMinute <= now }
        refreshJobArea()
        let open = ops.jobs.filter { !$0.isTaken }.count
        guard open < jobBoardSize, ops.jobArea.count >= 2 else { return }
        let count = min(jobBoardSize - open, ops.rng.int(1...3))
        for _ in 0..<count {
            if let job = makeJob(kind: pickJobKind()) { ops.jobs.append(job) }
        }
    }

    func biggestSeats() -> Int { max(4, aircraft.map(\.seats).max() ?? 4) }
    func biggestHold() -> Int { max(400, aircraft.map(\.cargoKg).max() ?? 400) }

    mutating func pickJobKind() -> JobKind {
        let month = clock.date.month
        let summer = month >= 5 && month <= 9
        let kinds: [JobKind] = [.medevac, .mail, .fuelDrums, .crewChange, .lodgeCharter, .survey, .freight]
        let weights: [Double] = [1.0, 2.0, 1.5, 1.2, summer ? 1.5 : 0.2, summer ? 1.0 : 0.3, 2.0]
        return kinds[ops.rng.weightedIndex(weights)]
    }

    /// Makes one job of a kind somewhere in the area, sized to what the fleet can carry. Nil if no sensible pair turned up.
    mutating func makeJob(kind: JobKind, near centre: String? = nil) -> Job? {
        let area = ops.jobArea.compactMap { AirportCatalog.airport($0) }
        guard area.count >= 2 else { return nil }
        let centreAirport = centre.flatMap { AirportCatalog.airport($0) }
        var from = centreAirport ?? area[ops.rng.int(0...(area.count - 1))]
        var to = area[ops.rng.int(0...(area.count - 1))]
        switch kind {
        case .medevac, .evacuation:
            // From a small place to the biggest town within reach.
            let smallPlaces = area.filter { $0.population < 20_000 }
            let source = centreAirport ?? (smallPlaces.isEmpty ? from : smallPlaces[ops.rng.int(0...(smallPlaces.count - 1))])
            from = source
            to = area.filter { $0.code != source.code && $0.distanceKm(to: source) <= 700 }.max { $0.population < $1.population } ?? to
        case .mail, .fuelDrums, .crewChange, .lodgeCharter, .filmCrew:
            // From a supply town to a small place.
            let towns = area.filter { $0.kind == .large || $0.kind == .medium || $0.code == airline.home }
            if !towns.isEmpty { from = towns[ops.rng.int(0...(towns.count - 1))] }
            let small = area.filter { $0.code != from.code && $0.population < 20_000 && $0.distanceKm(to: from) <= 700 }
            if !small.isEmpty { to = small[ops.rng.int(0...(small.count - 1))] }
        case .survey, .freight:
            break
        }
        let km = from.distanceKm(to: to)
        guard from.code != to.code, km >= 30, km <= 1500 else { return nil }

        let seats = biggestSeats()
        let hold = biggestHold()
        var passengers = 0
        var cargo = 0
        switch kind {
        case .medevac: passengers = 2
        case .mail: cargo = min(hold, ops.rng.int(80...400))
        case .fuelDrums: cargo = min(hold, ops.rng.int(300...1200))
        case .crewChange: passengers = min(seats, ops.rng.int(4...12))
        case .lodgeCharter: passengers = min(seats, ops.rng.int(2...6)); cargo = min(hold, 150)
        case .survey: passengers = 2; cargo = min(hold, 200)
        case .freight: cargo = min(hold, ops.rng.int(400...2500))
        case .evacuation: passengers = seats
        case .filmCrew: passengers = min(seats, ops.rng.int(4...8)); cargo = min(hold, 400)
        }
        let fare = Fares.market(from: from, to: to, distanceKm: km)
        let base = Double(passengers) * fare + Double(cargo) * Fares.cargoRate(distanceKm: km) + 2.5 * km
        let pay = Int((base * kind.payFactor).rounded())
        let hoursToFly = km / 300.0 + 1.0
        let deadlineHours: Double
        switch kind {
        case .medevac, .evacuation: deadlineHours = hoursToFly + 8
        case .mail: deadlineHours = 48
        default: deadlineHours = Double(ops.rng.int(48...120))
        }
        let deadline = clock.minute + Int(deadlineHours * 60)
        let expires = min(deadline - Int(hoursToFly * 60), clock.minute + (kind == .medevac ? 6 * 60 : 3 * GameClock.minutesPerDay))
        guard expires > clock.minute else { return nil }
        let id = ops.nextJobID
        ops.nextJobID += 1
        return Job(id: id, kind: kind, from: from.code, to: to.code, passengers: passengers, cargoKg: cargo, pay: pay,
                   deadlineMinute: deadline, expiresMinute: expires, aircraftID: nil, loaded: false)
    }
}
