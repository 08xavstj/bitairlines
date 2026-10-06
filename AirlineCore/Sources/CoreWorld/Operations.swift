// CoreWorld/Operations.swift: everything added on top of the first game: the game mode, perks, the fuel stock, punctuality, bases,
// the job board, events, slots, rival airlines, pilots and scenarios. It sits in World as one value that an older save does not have;
// anything missing reads as it would in a new game. It has its own random stream so the original simulation draws stay the same.
import CoreSim

public struct Operations: Sendable, Codable {
    public var mode: GameMode = .normal
    public var rng = SeededRandom(seed: 0x0B5E_ED0F)

    public var perks: [Perk] = []
    /// Perks on offer after a certificate upgrade, waiting for the player to pick one.
    public var perkChoices: [Perk] = []

    public var fuel = FuelStock()
    public var fuelHistory: [Double] = []
    public var onTime = OnTimeRecord()

    public var bases: [Base] = []

    public var jobs: [Job] = []
    public var nextJobID = 1
    public var jobsDone: [JobRecord] = []
    /// Airports within reach of the network (sorted codes), and the network it was worked out for.
    public var jobArea: [String] = []
    public var jobAreaKey = ""

    public var events: [ActiveEvent] = []
    public var offers: [EventOffer] = []
    public var nextEventID = 1

    public var slots: [SlotHolding] = []
    public var slotsUsedToday: [SlotHolding] = []

    public var rivals: [Rival] = []

    public var pilots: [Pilot] = []
    /// Pilots looking for work this week.
    public var pilotMarket: [Pilot] = []
    public var nextPilotID = 1
    public var autoHirePilots = true

    public var scenario: ScenarioState?

    /// This week's goal (see WeeklyGoals.swift) and how many have been met in this game.
    public var weeklyGoal: WeeklyGoal?
    public var goalsCompleted = 0

    public init() {}

    public init(mode: GameMode, seed: UInt64) {
        self.mode = mode
        rng = SeededRandom(seed: seed ^ 0x5A17_0F5E_ED00_0001)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Operations()
        mode = try c.decodeIfPresent(GameMode.self, forKey: .mode) ?? d.mode
        rng = try c.decodeIfPresent(SeededRandom.self, forKey: .rng) ?? d.rng
        perks = try c.decodeIfPresent([Perk].self, forKey: .perks) ?? []
        perkChoices = try c.decodeIfPresent([Perk].self, forKey: .perkChoices) ?? []
        fuel = try c.decodeIfPresent(FuelStock.self, forKey: .fuel) ?? d.fuel
        fuelHistory = try c.decodeIfPresent([Double].self, forKey: .fuelHistory) ?? []
        onTime = try c.decodeIfPresent(OnTimeRecord.self, forKey: .onTime) ?? d.onTime
        bases = try c.decodeIfPresent([Base].self, forKey: .bases) ?? []
        jobs = try c.decodeIfPresent([Job].self, forKey: .jobs) ?? []
        nextJobID = try c.decodeIfPresent(Int.self, forKey: .nextJobID) ?? 1
        jobsDone = try c.decodeIfPresent([JobRecord].self, forKey: .jobsDone) ?? []
        jobArea = try c.decodeIfPresent([String].self, forKey: .jobArea) ?? []
        jobAreaKey = try c.decodeIfPresent(String.self, forKey: .jobAreaKey) ?? ""
        events = try c.decodeIfPresent([ActiveEvent].self, forKey: .events) ?? []
        offers = try c.decodeIfPresent([EventOffer].self, forKey: .offers) ?? []
        nextEventID = try c.decodeIfPresent(Int.self, forKey: .nextEventID) ?? 1
        slots = try c.decodeIfPresent([SlotHolding].self, forKey: .slots) ?? []
        slotsUsedToday = try c.decodeIfPresent([SlotHolding].self, forKey: .slotsUsedToday) ?? []
        rivals = try c.decodeIfPresent([Rival].self, forKey: .rivals) ?? []
        pilots = try c.decodeIfPresent([Pilot].self, forKey: .pilots) ?? []
        pilotMarket = try c.decodeIfPresent([Pilot].self, forKey: .pilotMarket) ?? []
        nextPilotID = try c.decodeIfPresent(Int.self, forKey: .nextPilotID) ?? 1
        autoHirePilots = try c.decodeIfPresent(Bool.self, forKey: .autoHirePilots) ?? true
        scenario = try c.decodeIfPresent(ScenarioState.self, forKey: .scenario)
        weeklyGoal = try c.decodeIfPresent(WeeklyGoal.self, forKey: .weeklyGoal)
        goalsCompleted = try c.decodeIfPresent(Int.self, forKey: .goalsCompleted) ?? 0
    }
}

extension World {
    /// The added systems. An older save has none; reading gives what a new game would have, and the first change stores it.
    public var ops: Operations {
        get { operationsStore ?? Operations() }
        _modify {
            if operationsStore == nil { operationsStore = Operations() }
            yield &operationsStore!
        }
        set { operationsStore = newValue }
    }

    /// Brings a save from before the added systems up to date: crews for the fleet, rivals, a pilot market. Safe to call any time.
    mutating func upgradeOldSave() {
        guard operationsStore == nil else { return }
        operationsStore = Operations(mode: .normal, seed: rng.next())
        startOperations(freeCrews: true)
    }

    /// Sets up the added systems at the start of a game (or for an upgraded save).
    mutating func startOperations(freeCrews: Bool) {
        for i in aircraft.indices where aircraft[i].isDelivered { autoCrew(aircraftIndex: i, free: freeCrews) }
        makeRivals()
        refreshPilotMarket()
        refreshJobArea()
        ops.fuelHistory = [market.fuelIndex]
        startWeeklyGoal()
    }
}
