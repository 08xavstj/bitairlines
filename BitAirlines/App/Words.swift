import CoreCatalog
import CoreWorld

/// Names and one-line explanations for the things the player chooses between: kits, facilities, perks, service, modes, jobs,
/// events, pilot ratings and scenarios. Plain and specific.
enum Words {
    static func name(_ kit: Kit) -> String {
        switch kit {
        case .floats: "Floats"
        case .amphibious: "Amphibious floats"
        case .wheelSkis: "Wheel-skis"
        case .gravelKit: "Gravel kit"
        case .stolKit: "STOL kit"
        case .freighter: "Freighter conversion"
        }
    }

    static func explain(_ kit: Kit) -> String {
        switch kit {
        case .floats: "Lakes and rivers only. No runways."
        case .amphibious: "Lakes and runways. Costs more than plain floats."
        case .wheelSkis: "Runways all year, and frozen lakes in winter."
        case .gravelKit: "Lets an aircraft built for tarmac use gravel strips."
        case .stolKit: "Needs a quarter less runway."
        case .freighter: "Seats out, freight in."
        }
    }

    static func name(_ facility: Facility) -> String {
        switch facility {
        case .fuelDepot: "Fuel depot"
        case .hangar: "Hangar"
        case .lights: "Runway lights"
        case .runwayExtension: "Longer runway"
        case .paving: "Paving"
        case .hubTerminal: "Hub terminal"
        }
    }

    static func explain(_ facility: Facility) -> String {
        switch facility {
        case .fuelDepot: "No remote fuel premium here, room to stock fuel ahead, and fuel for sale in Realism."
        case .hangar: "Checks here take half as long and repairs cost less."
        case .lights: "Flights in the dark. Without lights a small strip is only open in daylight."
        case .runwayExtension: "\(Format.number(Tuning.runwayExtensionFt)) more feet of runway, so bigger aircraft fit."
        case .paving: "Turns the gravel into tarmac for aircraft that need a paved runway."
        case .hubTerminal: "Passengers change planes here between your routes."
        }
    }

    static func name(_ perk: Perk) -> String {
        switch perk {
        case .homeFuelDeal: "Home fuel deal"
        case .quickTurns: "Quick turns"
        case .goodName: "Good name"
        case .mechanicsGuild: "Mechanics' guild"
        case .permitOffice: "Permit office"
        case .pilotSchool: "Pilot school"
        case .freightNetwork: "Freight network"
        case .knownFace: "Known face"
        case .smallFieldDeal: "Small field deal"
        }
    }

    static func explain(_ perk: Perk) -> String {
        switch perk {
        case .homeFuelDeal: "Fuel at your home airport costs 15% less."
        case .quickTurns: "Turnarounds take a quarter less time."
        case .goodName: "Reputation grows 30% faster."
        case .mechanicsGuild: "Maintenance costs 10% less and checks take half as long."
        case .permitOffice: "Permits cost half."
        case .pilotSchool: "Hiring and training pilots costs half."
        case .freightNetwork: "Freight pays 10% more."
        case .knownFace: "5% more people choose you on every route."
        case .smallFieldDeal: "Fees at small strips and seaplane bases are a quarter lower."
        }
    }

    static func name(_ level: ServiceLevel) -> String {
        switch level {
        case .basic: "Basic"
        case .standard: "Standard"
        case .premium: "Premium"
        }
    }

    static func name(_ mode: GameMode) -> String {
        switch mode {
        case .easy: "Easy"
        case .normal: "Normal"
        case .realism: "Realism"
        case .sandbox: "Sandbox"
        }
    }

    static func explain(_ mode: GameMode) -> String {
        switch mode {
        case .easy: "Any aircraft lands on any runway. No weather, no dark strips, no frozen lakes, no slots."
        case .normal: "Runway length and surface matter. Weather, daylight at small strips, lakes that freeze, slots at busy airports."
        case .realism: "Normal, and fuel is only sold at real fuel stops. Plan chains of small strips or build fuel depots."
        case .sandbox: "Money never runs out and every certificate level is open. For building and painting."
        }
    }

    static func name(_ kind: JobKind) -> String {
        switch kind {
        case .medevac: "Medevac"
        case .mail: "Mail run"
        case .fuelDrums: "Fuel drums"
        case .crewChange: "Crew change"
        case .lodgeCharter: "Lodge charter"
        case .survey: "Survey flight"
        case .freight: "Freight"
        case .evacuation: "Evacuation"
        case .filmCrew: "Film crew"
        }
    }

    static func name(_ kind: EventKind) -> String {
        switch kind {
        case .forestFire: "Forest fire"
        case .earlyThaw: "Early thaw"
        case .volcanicAsh: "Volcanic ash"
        case .filmCrew: "Film crew in town"
        case .winterGames: "Winter games"
        case .oilShock: "Oil shock"
        case .miningBoom: "Mining boom"
        }
    }

    static func explain(_ kind: EventKind, place: String) -> String {
        switch kind {
        case .forestFire: "A fire near \(Place.name(place)). Evacuation flights are on the job board."
        case .earlyThaw: "The ice road near \(Place.name(place)) closed early. Freight there is in demand for a month."
        case .volcanicAsh: "Ash closed airports around \(Place.name(place)) for a few days."
        case .filmCrew: "A film crew wants a charter from near \(Place.name(place)). See the job board."
        case .winterGames: "\(Place.name(place)) hosts the winter games: more travellers for two weeks."
        case .oilShock: "Oil prices jumped. Fuel costs more for a while."
        case .miningBoom: "A mine opened near \(Place.name(place)). More people and freight for six months."
        }
    }

    static func name(_ group: RatingGroup) -> String {
        switch group {
        case .singles: "Single-engine"
        case .twinProps: "Twin turboprops"
        case .pistonTwins: "Piston twins"
        case .regionalJets: "Regional jets"
        case .narrowbodies: "Narrowbody jets"
        case .widebodies: "Widebody jets"
        }
    }

    static func name(_ id: ScenarioID) -> String {
        switch id {
        case .freezeUp: "Before freeze-up"
        case .deltaVillages: "The delta villages"
        case .airAmbulance: "Air ambulance"
        case .islandHopper: "Island hopper"
        case .bushToJets: "Bush to jets"
        case .bigCarrier: "Big carrier"
        }
    }

    static func goal(_ def: ScenarioDefinition) -> String {
        switch def.goal {
        case .freightToRegion(_, _, let kg): return "Fly \(Format.number(kg / 1000)) tonnes of freight to Nunavut communities from \(Place.name(def.home)) before the sea ice closes in."
        case .serveAirports(let near, let radius, let count): return "Fly routes to \(count) airports within \(Int(radius)) km of \(Place.name(near))."
        case .jobs(let kind, let count): return "Finish \(count) \(name(kind).lowercased()) jobs from \(Place.name(def.home))."
        case .profitableJetRoute: return "Start in \(Place.name(def.home)) with a Caravan and run a jet route that makes money."
        case .reachLevel(let level): return "Grow from \(Place.name(def.home)) to certificate level \(level)."
        }
    }

    static func name(_ medal: Medal) -> String {
        switch medal {
        case .gold: "Gold"
        case .silver: "Silver"
        case .bronze: "Bronze"
        }
    }
}

// MARK: Rare finds on the used market
extension Words {
    static func name(_ find: RareFind) -> String {
        switch find {
        case .lowHours: "Low hours"
        case .heritage: "Heritage aircraft"
        case .barnFind: "Barn find"
        }
    }

    static func explain(_ find: RareFind) -> String {
        switch find {
        case .lowHours: "Low hours: barely flown, priced to sell."
        case .heritage: "Heritage: arrives in a historic paint scheme."
        case .barnFind: "Barn find: cheap, but it needs a lot of work."
        }
    }

    /// The name of a special livery. Heritage finds arrive with a code; names the player typed are shown as they are.
    static func liveryName(_ name: String) -> String {
        if let earned = CalendarWords.liveryName(name) { return earned }
        return name == RareFinds.heritageLiveryCode ? "Heritage" : name
    }
}
