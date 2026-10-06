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

    /// Marketing campaigns running (Marketing.swift) and the staff on the payroll (Staff.swift).
    public var campaigns: [ActiveCampaign] = []
    public var staff: [StaffRole] = []

    /// This week's and last week's reputation bookkeeping (Reputation.swift); started on first use.
    public var reputationBook: ReputationBook?

    /// The real calendar (RealDay.swift): today's real day as the app last passed it in (0 until then), the daily dispatch
    /// stamps (DailyDispatch.swift), the real-week goal (RealWeekGoal.swift), seasonal events (SeasonalEvents.swift),
    /// the liveries those unlocked, and the logbook of types and airports (Collections.swift).
    public var realDay = 0
    public var dispatch = DispatchBook()
    public var realWeekGoal: WeeklyGoal?
    public var realWeekGoalsMet = 0
    public var season = SeasonBook()
    public var unlockedLiveries: [String] = []
    public var logbook = Logbook()

    /// Rewards earned by watching an ad, for their caps, and the sponsor boost in hand (Rewards.swift).
    public var rewards = RewardState()

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
        campaigns = try c.decodeIfPresent([ActiveCampaign].self, forKey: .campaigns) ?? []
        staff = try c.decodeIfPresent([StaffRole].self, forKey: .staff) ?? []
        reputationBook = try c.decodeIfPresent(ReputationBook.self, forKey: .reputationBook)
        realDay = try c.decodeIfPresent(Int.self, forKey: .realDay) ?? 0
        dispatch = try c.decodeIfPresent(DispatchBook.self, forKey: .dispatch) ?? DispatchBook()
        realWeekGoal = try c.decodeIfPresent(WeeklyGoal.self, forKey: .realWeekGoal)
        realWeekGoalsMet = try c.decodeIfPresent(Int.self, forKey: .realWeekGoalsMet) ?? 0
        season = try c.decodeIfPresent(SeasonBook.self, forKey: .season) ?? SeasonBook()
        unlockedLiveries = try c.decodeIfPresent([String].self, forKey: .unlockedLiveries) ?? []
        logbook = try c.decodeIfPresent(Logbook.self, forKey: .logbook) ?? Logbook()
        rewards = try c.decodeIfPresent(RewardState.self, forKey: .rewards) ?? RewardState()
    }
}

extension World {
    /// The added systems. An older save has none; reading gives what a new game would have, and the first change stores it.
    public var ops: Operations {
        get { operationsStore ?? Operations() }
        _modify {
            // An older save gets the full upgrade (crews, rivals, a pilot market) before its first change, not a bare default.
            if operationsStore == nil { upgradeOldSave() }
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
