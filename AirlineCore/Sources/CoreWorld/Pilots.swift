// CoreWorld/Pilots.swift: pilots as people. Each has type ratings and logged hours, draws a monthly salary (on top of flight pay,
// which is in the leg costs), now and then is off sick, and can be trained on a new type. An aircraft needs enough rated pilots who
// are not sick or training; spare rated pilots step in. With automatic hiring on, a new aircraft comes with the pilots it needs.
import CoreCatalog
import CoreSim

public enum RatingGroup: String, Sendable, Hashable, Codable, CaseIterable {
    case singles, twinProps, pistonTwins, regionalJets, narrowbodies, widebodies

    public static func of(_ family: SpriteFamily) -> RatingGroup {
        switch family {
        case .lightSingle, .utilitySingle, .floatSingle: .singles
        case .twinTurboprop, .floatTwin, .commuter, .regionalTurboprop: .twinProps
        case .taildragger: .pistonTwins
        case .regionalJet, .rearEngineMainline: .regionalJets
        case .narrowbody: .narrowbodies
        case .widebody, .jumbo, .superJumbo: .widebodies
        }
    }

    /// 1 for the small types up to 4 for the big jets: scales pay, hiring and training.
    public var tier: Int {
        switch self {
        case .singles: 1
        case .twinProps, .pistonTwins: 2
        case .regionalJets, .narrowbodies: 3
        case .widebodies: 4
        }
    }
}

public struct Pilot: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var name: String
    public var ratings: [RatingGroup]
    public var hours: Double
    /// The aircraft this pilot normally flies.
    public var aircraftID: Int?
    public var sickUntilMinute: Int
    public var trainingUntilMinute: Int
    public var trainingFor: RatingGroup?
    public var salaryPerMonth: Int
    /// What it costs to hire this pilot (for candidates on the market).
    public var hireFee: Int

    public func isAvailable(at minute: Int) -> Bool { sickUntilMinute <= minute && trainingUntilMinute <= minute }
    public func isRated(_ group: RatingGroup) -> Bool { ratings.contains(group) }
}

extension World {
    static let firstNames = ["Ada", "Ben", "Cora", "Dev", "Elsie", "Finn", "Grace", "Hamid", "Ina", "Jonas", "Kaya", "Liam", "Mina", "Noah", "Olu",
                             "Pita", "Quinn", "Rosa", "Sami", "Tara", "Uki", "Vera", "Wes", "Ximena", "Yuki", "Zane", "Ayla", "Bram", "Cleo", "Dara"]
    static let lastNames = ["Akpik", "Bergen", "Cardinal", "Dumont", "Eriksen", "Fraser", "Gray", "Haldane", "Ikaksak", "Janvier", "Kowalski", "Lafferty",
                            "Mackenzie", "Nakamura", "Okafor", "Pokiak", "Quill", "Rasmussen", "Silva", "Tetso", "Ulu", "Vance", "Whitford", "Yarrow", "Zeller"]

    /// Pilots one aircraft of this type needs: two crews for the big types that fly long days.
    public static func pilotsNeeded(_ type: AircraftType) -> Int { type.pilots * (type.level >= 4 ? 2 : 1) }

    func salary(for group: RatingGroup) -> Int { Tuning.pilotSalaryPerMonth * group.tier }

    mutating func makePilot(group: RatingGroup, hours: Double? = nil) -> Pilot {
        let first = World.firstNames[ops.rng.int(0...(World.firstNames.count - 1))]
        let last = World.lastNames[ops.rng.int(0...(World.lastNames.count - 1))]
        let id = ops.nextPilotID
        ops.nextPilotID += 1
        let logged: Double = hours ?? Double(ops.rng.int(300...6000))
        let experience: Double = 0.8 + logged / 10_000
        let baseFee = Double(Tuning.pilotHireFee * group.tier)
        let fee = Int(baseFee * experience * pilotCostFactor)
        return Pilot(id: id, name: "\(first) \(last)", ratings: [group], hours: logged, aircraftID: nil, sickUntilMinute: 0, trainingUntilMinute: 0,
                     trainingFor: nil, salaryPerMonth: salary(for: group), hireFee: fee)
    }

    /// Weekly: a fresh handful of pilots looking for work, mostly rated on what the airline flies.
    mutating func refreshPilotMarket() {
        var flown: [RatingGroup] = []
        for plane in aircraft {
            guard let type = plane.type else { continue }
            let group = RatingGroup.of(type.family)
            if !flown.contains(group) { flown.append(group) }
        }
        let topTier = max(1, (airline.level + 1) / 2 + 1)
        let allowed = RatingGroup.allCases.filter { $0.tier <= topTier }
        ops.pilotMarket = []
        for _ in 0..<6 {
            var group: RatingGroup
            if !flown.isEmpty && ops.rng.chance(0.7) {
                group = flown[ops.rng.int(0...(flown.count - 1))]
            } else {
                group = allowed[ops.rng.int(0...(allowed.count - 1))]
            }
            ops.pilotMarket.append(makePilot(group: group))
        }
    }

    public mutating func hirePilot(id: Int) throws {
        guard let c = ops.pilotMarket.firstIndex(where: { $0.id == id }) else { throw WorldError.invalidChoice }
        let pilot = ops.pilotMarket[c]
        guard airline.cash >= pilot.hireFee else { throw WorldError.notEnoughCash(needed: pilot.hireFee) }
        spendOnOverhead(pilot.hireFee)
        ops.pilotMarket.remove(at: c)
        ops.pilots.append(pilot)
        addNews(.pilotHired, subject: pilot.name, amount: pilot.id)
    }

    public mutating func dismissPilot(id: Int) throws {
        guard let p = ops.pilots.firstIndex(where: { $0.id == id }) else { throw WorldError.invalidChoice }
        ops.pilots.remove(at: p)
    }

    public func trainingPrice(_ group: RatingGroup) -> Int { Int(Double(Tuning.pilotTrainingPrice * group.tier) * pilotCostFactor) }
    public static func trainingDays(_ group: RatingGroup) -> Int { 10 + 10 * group.tier }

    /// Sends a pilot on a type course: away for a few weeks, then rated.
    public mutating func train(pilotID: Int, for group: RatingGroup) throws {
        guard let p = ops.pilots.firstIndex(where: { $0.id == pilotID }) else { throw WorldError.invalidChoice }
        guard !ops.pilots[p].isRated(group), ops.pilots[p].trainingFor == nil else { throw WorldError.alreadyBuilt }
        let price = trainingPrice(group)
        guard airline.cash >= price else { throw WorldError.notEnoughCash(needed: price) }
        spendOnOverhead(price)
        ops.pilots[p].trainingFor = group
        ops.pilots[p].trainingUntilMinute = clock.minute + World.trainingDays(group) * GameClock.minutesPerDay
        ops.pilots[p].aircraftID = nil
    }

    public mutating func setAutoHire(_ on: Bool) { ops.autoHirePilots = on }

    /// Rated pilots the aircraft can call on right now: its own crew first, then spares rated on the type.
    func availableCrew(for i: Int) -> [Int] {
        guard let type = aircraft[i].type else { return [] }
        let group = RatingGroup.of(type.family)
        let id = aircraft[i].id
        let own = ops.pilots.filter { $0.aircraftID == id && $0.isRated(group) && $0.isAvailable(at: clock.minute) }.map(\.id)
        let spare = ops.pilots.filter { $0.aircraftID == nil && $0.isRated(group) && $0.isAvailable(at: clock.minute) }.map(\.id)
        return own + spare
    }

    /// Whether the aircraft has the pilots to fly now. Spares who step in join its crew.
    mutating func crewReady(_ i: Int) -> Bool {
        guard let type = aircraft[i].type else { return false }
        let needed = type.pilots
        let crew = availableCrew(for: i)
        guard crew.count >= needed else { return false }
        for pid in crew.prefix(needed) {
            if let p = ops.pilots.firstIndex(where: { $0.id == pid }), ops.pilots[p].aircraftID == nil { ops.pilots[p].aircraftID = aircraft[i].id }
        }
        return true
    }

    /// When the first rated pilot who is sick or on a course will be back (nil if the airline has no rated pilot at all).
    func crewBackMinute(_ i: Int) -> Int? {
        guard let type = aircraft[i].type else { return nil }
        let group = RatingGroup.of(type.family)
        let returns = ops.pilots.filter { $0.isRated(group) || $0.trainingFor == group }.map { max($0.sickUntilMinute, $0.trainingUntilMinute) }
        return returns.filter { $0 > clock.minute }.min()
    }

    /// Logs flying hours for the crew of an aircraft.
    mutating func logHours(_ i: Int, minutes: Int) {
        guard let type = aircraft[i].type else { return }
        var left = type.pilots
        for p in ops.pilots.indices where left > 0 && ops.pilots[p].aircraftID == aircraft[i].id && ops.pilots[p].isAvailable(at: clock.minute) {
            ops.pilots[p].hours += Double(minutes) / 60.0
            left -= 1
        }
    }

    /// Hires the pilots a newly arrived aircraft needs (free for the founding crew).
    mutating func autoCrew(aircraftIndex i: Int, free: Bool) {
        guard free || ops.autoHirePilots, let type = aircraft[i].type else { return }
        let group = RatingGroup.of(type.family)
        let have = ops.pilots.filter { $0.aircraftID == aircraft[i].id && $0.isRated(group) }.count
        for _ in 0..<max(0, World.pilotsNeeded(type) - have) {
            var pilot = makePilot(group: group)
            if !free { spendOnOverhead(pilot.hireFee) }
            pilot.aircraftID = aircraft[i].id
            ops.pilots.append(pilot)
        }
    }

    /// Once a week: sickness, finished courses, a new pilot market.
    mutating func weeklyPilots() {
        for p in ops.pilots.indices {
            if let group = ops.pilots[p].trainingFor, ops.pilots[p].trainingUntilMinute <= clock.minute {
                ops.pilots[p].ratings.append(group)
                ops.pilots[p].trainingFor = nil
                ops.pilots[p].salaryPerMonth = max(ops.pilots[p].salaryPerMonth, salary(for: group))
            }
            if ops.rng.chance(Tuning.pilotSickChancePerWeek) {
                ops.pilots[p].sickUntilMinute = clock.minute + ops.rng.int(2...6) * GameClock.minutesPerDay
                addNews(.pilotSick, subject: ops.pilots[p].name, amount: ops.pilots[p].id)
            }
        }
        // Pilots of an aircraft that has gone are spares now.
        let ids = Set(aircraft.map(\.id))
        for p in ops.pilots.indices where ops.pilots[p].aircraftID.map({ !ids.contains($0) }) == true { ops.pilots[p].aircraftID = nil }
        refreshPilotMarket()
    }

    /// What all pilots cost a month.
    public var pilotPayroll: Int { ops.pilots.reduce(0) { $0 + $1.salaryPerMonth } }
}
