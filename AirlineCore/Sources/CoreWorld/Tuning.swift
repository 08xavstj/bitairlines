// CoreWorld/Tuning.swift: every balance number lives here. Calibrated with tools/sim/demand_proto.py and tools/sim/route_proto.py;
// change a number here, then bump WorldInfo.rulesVersion.
import CoreCatalog
import CoreSim

public enum Tuning {
    // MARK: Passenger demand
    /// Trips per person per year for wealth tier 1...5.
    public static let propensity: [Double] = [0.02, 0.08, 0.30, 1.00, 2.00]
    /// How much more a fly-in community (isolation 1) travels than a town with roads.
    public static let isolationBoost = 3.0
    /// Overall scale, fitted to real route traffic (Sydney-Melbourne, London-New York, Inuvik-Yellowknife and others).
    public static let demandConstant = 2.0
    /// People beyond this do not add demand to one airport: a megacity's far suburbs use its other airports, drive or take trains.
    public static let populationCap = 9_000_000
    /// Population enters as pop^(7/8).
    public static let populationEighths = 7
    /// Share of the base flow still flown at a distance in km (cars and trains win short hops).
    public static let distanceShare = LinearTable([
        (0, 0.0), (50, 0.10), (150, 0.38), (300, 0.62), (600, 1.0), (1200, 0.85), (2500, 0.55),
        (5000, 0.38), (9000, 0.28), (15000, 0.2), (20100, 0.15),
    ])
    /// Catchment population above which an airport counts as having road and rail alternatives (isolation falls to 0).
    public static let isolationPopulation = 20000.0
    /// Isolation of a paved airport relative to a gravel strip or lake of the same size.
    public static let pavedIsolationFactor = 0.6

    // MARK: Fares (US dollars, economy, one way)
    public static let fareByDistance = LinearTable([
        (0, 25), (50, 45), (100, 70), (200, 105), (400, 150), (800, 210), (1500, 290),
        (3000, 420), (6000, 640), (10000, 860), (16000, 1150),
    ])
    public static let fareScale = 0.85
    /// Fly-in communities pay up to this much more.
    public static let isolationFarePremium = 1.1

    // MARK: Cargo
    public static let cargoConstant = 0.18
    public static let cargoBaseShare = 0.1
    public static let cargoIsolationShare = 3.0
    public static let cargoRateByDistance = LinearTable([(0, 1.2), (100, 2.0), (400, 2.6), (1000, 3.2), (3000, 3.5), (10000, 3.8)])
    /// Usable fraction of a hold's capacity on an ordinary day.
    public static let cargoLoadLimit = 0.7
    /// A route never drops below this share of its potential, and a new one starts here.
    public static let minimumMaturity = 0.5

    // MARK: Operating costs (US dollars)
    public static let jetFuelPerKg = 1.00
    public static let avgasPerKg = 1.90
    public static let pilotPerBlockHour = 110.0
    public static let cabinCrewPerBlockHour = 45.0
    public static let handlingPerPassenger = 14.0
    /// Commissions and card fees as a share of ticket revenue.
    public static let salesShare = 0.05
    /// Peak-day spill: the average flight is never perfectly full.
    public static let loadFactorCap = 0.88
    public static let landingFeePerTonne: [AirportKind: Double] = [.large: 14, .medium: 8, .small: 4, .seaplane: 3]
    public static let minimumLandingFee = 40.0
    public static let passengerFee: [AirportKind: Double] = [.large: 5, .medium: 3, .small: 2, .seaplane: 1.5]
    /// Extra fuel cost at an airport (remote fields pay barge and air freight prices).
    public static let fuelPremium: [AirportKind: Double] = [.large: 0, .medium: 0.10, .small: 0.35, .seaplane: 0.40]
    public static let navigationPerKm = 0.9
    /// Fixed daily cost per airline and per aircraft (admin, insurance), plus insurance as a share of hull value per year.
    /// Head office costs per day grow with the size of the operation: a one-plane bush airline has a desk, a jumbo carrier has a headquarters.
    public static func headOfficePerDay(level: Int) -> Double { 120.0 * Double(level * level) }
    public static let adminPerAircraftPerDay = 120.0
    public static let insuranceShareOfPricePerYear = 0.0025

    public static let cargoHandlingPerKg = 0.06

    // MARK: Wear, breakdowns and the market
    /// Condition points lost per block hour (100 is perfect).
    public static let conditionLossPerBlockHour = 0.012
    /// Below this the aircraft is taken out of service for a scheduled check.
    public static let maintenanceThreshold = 55.0
    public static let conditionAfterCheck = 96.0
    /// Chance per departure of a failure on the ground, before the wear multiplier (1 for new, up to 4 for worn out).
    public static let breakdownPerDeparture = 0.00015
    /// How fast waiting passengers lose patience: the bucket is divided by 1 + this x days waited.
    public static let waitingDecayPerDay = 0.25
    public static let overdraftLimit = 100_000
    public static let daysOverdrawnBeforeBankruptcy = 14
    public static let emergencyLoanAmount = 250_000
    public static let emergencyLoanRate = 0.15
    /// Catchment above which a market has competing airlines (the share a newcomer gets is then limited).
    public static let competitiveCatchment = 1_500_000.0
    /// A used aircraft arrives after its listing's estimate (2 to 9) times this many hours: 4 to 18 hours.
    public static let usedDeliveryHoursPerStep = 2
    /// A new aircraft arrives after base + per level x its level hours: a day for a bush plane, 4 days for a jumbo.
    public static let newDeliveryBaseHours = 12
    public static let newDeliveryHoursPerLevel = 12

    // MARK: Bases, fuel stock and slots
    public static let runwayExtensionFt = 1500
    /// Fuel the airline can stock without a depot, and how much each depot adds, in kilograms.
    public static let fuelStorageBaseKg = 20_000.0
    public static let fuelStoragePerDepotKg = 150_000.0
    /// Airports from this certificate level up hand out slots.
    public static let slotAirportLevel = 3
    /// Price of one daily slot at the smallest slot airport (bigger ones cost the square of their tier times this).
    public static let slotBasePrice = 60_000

    // MARK: Jobs and events
    /// Jobs and events happen at airports within this distance of the network.
    public static let jobAreaKm = 600.0
    public static let jobRecordsKept = 300
    public static let eventChancePerWeek = 0.2

    // MARK: Hubs
    /// Through passengers only take a connection that is at most this much longer than flying direct.
    public static let maxConnectionDetour = 1.6
    /// Share of the A to B market that will change planes at a hub.
    public static let connectingShare = 0.5
    /// Through fares are a little cheaper than the going direct fare.
    public static let connectingFareDiscount = 0.9

    // MARK: Rival airlines
    /// Chance each month that a rival moves into one of the player's busy routes.
    public static let rivalEntryChance = 0.15
    /// A leg must have at least this many people a day before a rival bothers.
    public static let rivalEntryPaxPerDay = 60.0
    /// Share of a market a rival is assumed to carry (for the rankings).
    public static let rivalMarketShare = 0.3
    /// Where a rival flies the same pair, competition is at least this intense.
    public static let rivalIntensity = 0.35

    // MARK: Pilots
    /// Monthly base salary for a pilot on small types (bigger types pay a multiple); flight pay is in the leg costs.
    public static let pilotSalaryPerMonth = 2_000
    public static let pilotHireFee = 6_000
    public static let pilotTrainingPrice = 20_000
    public static let pilotSickChancePerWeek = 0.015

    // MARK: Sandbox
    public static let sandboxStartCash = 1_000_000_000
    public static let sandboxCashFloor = 100_000_000
    public static let sandboxTopUp = 900_000_000

    // MARK: Turnaround and utilisation
    public static func turnaroundHours(_ engine: EngineKind) -> Double {
        switch engine {
        case .piston: 0.4
        case .turboprop: 0.5
        case .jet: 0.75
        }
    }

    /// The most block hours an aircraft of a certificate level flies in a day.
    public static func maxBlockHoursPerDay(level: Int) -> Double {
        switch level {
        case 1: 9
        case 2, 3: 10
        case 4: 11
        case 5: 12
        default: 14
        }
    }
}
