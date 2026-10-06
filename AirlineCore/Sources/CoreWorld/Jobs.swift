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

    /// Work that carries people (sized by seats); the rest carries freight (sized by the hold).
    var carriesPeople: Bool {
        switch self {
        case .medevac, .crewChange, .lodgeCharter, .survey, .evacuation, .filmCrew: true
        case .mail, .fuelDrums, .freight: false
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

// MARK: Job board
extension Tuning {
    /// A job area with fewer airports than this in the countries the airline holds permits for also takes the airports within
    /// reach across the border, so a home near a border (Punta Arenas) still gets jobs and a daily dispatch.
    static let jobAreaMinimumAirports = 3
    /// A medevac stays on offer this many game hours, and must land within the flight time plus this many more hours.
    static let medevacOfferHours = 12
    static let medevacSlackHours = 2
}

extension World {
    /// How many offers the board holds at once.
    var jobBoardSize: Int { 6 + 2 * airline.level }

    /// The airports jobs come from: the home, every stop the airline flies to and its bases.
    var servedAirports: [String] {
        Array(Set([airline.home] + routes.flatMap { $0.stops } + ops.bases.map(\.airport))).sorted()
    }

    /// Recomputes the airports within reach of the network (where jobs and events happen) when the network has changed.
    /// Near a border the permitted countries may hold almost nothing within reach (every strip near Punta Arenas is in
    /// Argentina); one-off jobs need no route permit, so the area then reaches across the border.
    mutating func refreshJobArea() {
        // "v2" makes saves from before the border rule work their area out again once.
        let key = "v2|" + servedAirports.joined(separator: ",") + "|\(airline.level)|\(airline.permits.sorted().joined())"
        guard key != ops.jobAreaKey else { return }
        let served = servedAirports.compactMap { AirportCatalog.airport($0) }
        var area = airportsInReach(of: served, anyCountry: false)
        if area.count < Tuning.jobAreaMinimumAirports { area = airportsInReach(of: served, anyCountry: true) }
        ops.jobArea = area
        ops.jobAreaKey = key
    }

    /// The airports within `Tuning.jobAreaKm` of any of `served` that the airline's level allows (and the home), sorted; only in
    /// countries it holds permits for unless `anyCountry`.
    func airportsInReach(of served: [Airport], anyCountry: Bool) -> [String] {
        let reachDegrees = Tuning.jobAreaKm / 111.0
        var area: [String] = []
        for airport in AirportCatalog.all where anyCountry || airline.permits.contains(airport.country) {
            // Cheap latitude test first; the great-circle distance only for airports that pass it.
            let near = served.contains { s in
                let dLat = s.latitude - airport.latitude
                return dLat <= reachDegrees && dLat >= -reachDegrees && s.distanceKm(to: airport) <= Tuning.jobAreaKm
            }
            guard near else { continue }
            if Progression.requiredLevel(for: airport) <= airline.level || airport.code == airline.home { area.append(airport.code) }
        }
        return area.sorted()
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

    /// The most seats and the biggest hold in the delivered fleet (an aircraft on order does not count yet).
    func biggestSeats() -> Int { max(4, aircraft.filter(\.isDelivered).map(\.seats).max() ?? 4) }
    func biggestHold() -> Int { max(400, aircraft.filter(\.isDelivered).map(\.cargoKg).max() ?? 400) }

    mutating func pickJobKind() -> JobKind {
        let month = clock.date.month
        let summer = month >= 5 && month <= 9
        let kinds: [JobKind] = [.medevac, .mail, .fuelDrums, .crewChange, .lodgeCharter, .survey, .freight]
        let weights: [Double] = [1.0, 2.0, 1.5, 1.2, summer ? 1.5 : 0.2, summer ? 1.0 : 0.3, 2.0]
        return kinds[ops.rng.weightedIndex(weights)]
    }

    /// Makes one job of a kind somewhere in the area, sized to an aircraft in the fleet that can fly it (to the fleet's biggest
    /// when none can). Nil if no sensible pair turned up. A job only leaves from an airport the airline may depart from (slots).
    mutating func makeJob(kind: JobKind, near centre: String? = nil) -> Job? {
        let area = ops.jobArea.compactMap { AirportCatalog.airport($0) }
        guard area.count >= 2 else { return nil }
        let pickups = area.filter { canDepartOnJob(from: $0) }
        guard !pickups.isEmpty else { return nil }
        let centreAirport = centre.flatMap { AirportCatalog.airport($0) }
        var from = centreAirport ?? pickups[ops.rng.int(0...(pickups.count - 1))]
        var to = area[ops.rng.int(0...(area.count - 1))]
        switch kind {
        case .medevac, .evacuation:
            // From a small place to the biggest town within reach.
            let smallPlaces = pickups.filter { $0.population < 20_000 }
            let source = centreAirport ?? (smallPlaces.isEmpty ? from : smallPlaces[ops.rng.int(0...(smallPlaces.count - 1))])
            from = source
            to = area.filter { $0.code != source.code && $0.distanceKm(to: source) <= 700 }.max { $0.population < $1.population } ?? to
        case .mail, .fuelDrums, .crewChange, .lodgeCharter, .filmCrew:
            // From a supply town to a small place.
            let towns = pickups.filter { $0.kind == .large || $0.kind == .medium || $0.code == airline.home }
            if !towns.isEmpty { from = towns[ops.rng.int(0...(towns.count - 1))] }
            let small = area.filter { $0.code != from.code && $0.population < 20_000 && $0.distanceKm(to: from) <= 700 }
            if !small.isEmpty { to = small[ops.rng.int(0...(small.count - 1))] }
        case .survey, .freight:
            break
        }
        let km = from.distanceKm(to: to)
        guard from.code != to.code, km >= 30, km <= 1500, canDepartOnJob(from: from) else { return nil }

        // The load fits one aircraft that can fly this pair, so the job is never too big for every aircraft that could do it.
        let sizer = jobSizingPlane(kind: kind, from: from, to: to)
        let seats = sizer?.seats ?? biggestSeats()
        let hold = sizer?.cargoKg ?? biggestHold()
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
        case .medevac: deadlineHours = hoursToFly + Double(Tuning.medevacOfferHours + Tuning.medevacSlackHours)
        case .evacuation: deadlineHours = hoursToFly + 8
        case .mail: deadlineHours = 48
        default: deadlineHours = Double(ops.rng.int(48...120))
        }
        let deadline = clock.minute + Int(deadlineHours * 60)
        let offerMinutes = kind == .medevac ? Tuning.medevacOfferHours * 60 : 3 * GameClock.minutesPerDay
        let expires = min(deadline - Int(hoursToFly * 60), clock.minute + offerMinutes)
        guard expires > clock.minute else { return nil }
        let id = ops.nextJobID
        ops.nextJobID += 1
        return Job(id: id, kind: kind, from: from.code, to: to.code, passengers: passengers, cargoKg: cargo, pay: pay,
                   deadlineMinute: deadline, expiresMinute: expires, aircraftID: nil, loaded: false)
    }
}
