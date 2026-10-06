import CoreCatalog
import CoreWorld

/// The words for what the core reports. Plain and specific; no hype.
enum Messages {
    static func describe(_ error: WorldError) -> String {
        switch error {
        case .unknownAirport(let code): return "No airport with the code \(code)."
        case .unknownType: return "That aircraft model is not known."
        case .unknownAircraft: return "That aircraft is gone."
        case .unknownRoute: return "That route is gone."
        case .unknownListing: return "Someone else bought that aircraft."
        case .unknownIssue: return "That problem has already been dealt with."
        case .notEnoughCash(let needed): return "You need \(Format.dollars(needed)) more."
        case .levelTooLow(let level): return "Needs certificate level \(level)."
        case .airportLevelTooHigh(let airport, let required): return "\(Place.name(airport)) is too busy for you yet. It needs certificate level \(required)."
        case .permitRequired(let country, let price): return "You need a permit for \(CountryCatalog.country(country)?.name ?? country): \(Format.dollars(price))."
        case .routeNeedsTwoStops: return "A route needs at least two airports."
        case .tooManyStops: return "A route can have at most \(World.maxStops) stops."
        case .duplicateStops: return "Each airport can appear once in a route."
        case .aircraftCannotUse(let airport): return "This aircraft cannot use \(Place.name(airport)): the runway is too short or the wrong surface."
        case .outOfRange(let km): return "Too far for this aircraft (\(Format.number(km)) km)."
        case .notDelivered: return "That aircraft has not arrived yet."
        case .aircraftBusy: return "That aircraft is busy right now."
        case .aircraftHasRoute: return "Take the aircraft off its route first."
        case .notInProduction: return "That model is no longer built. Look for a used one."
        case .invalidChoice: return "That choice is not available."
        case .requirementsNotMet: return "You do not meet the requirements yet."
        case .alreadyHasPermit: return "You already have that permit."
        case .invalidAmount: return "That amount is not allowed."
        case .fuelStorageFull(let kg): return "Your tanks hold \(Format.number(kg)) kg. Build a fuel depot for more room."
        case .noFuel(let airport): return "No fuel for long enough after \(Place.name(airport)). Add a fuel stop or build a fuel depot."
        case .alreadyBuilt: return "That is already done."
        case .campaignRunning: return "That campaign is already running."
        case .needsARoute: return "Open a route first: there is nothing to advertise yet."
        case .alreadyHired: return "You already have someone in that job."
        case .notHired: return "Nobody has that job."
        case .cannotBuildHere: return "That cannot be done here."
        case .kitDoesNotFit: return "That kit is not made for this aircraft."
        case .jobUnavailable: return "That job is no longer on offer."
        case .notEnoughRoom: return "This aircraft has too few seats or too small a hold for the job."
        case .routesDoNotMeet: return "That route does not touch any airport this aircraft already flies to."
        case .tooManyRoutes: return "An aircraft can fly at most \(World.maxRoutesPerAircraft) routes."
        case .isHeadquarters: return "This is your headquarters. Move the headquarters first, from the Airline screen."
        }
    }

    static func name(_ choice: IssueChoice) -> String {
        switch choice {
        case .repairNow: return "Repair now"
        case .flyInMechanic: return "Fly in a mechanic"
        case .waitForParts: return "Wait for parts"
        case .emergencyLoan: return "Emergency loan"
        case .declareBankruptcy: return "Declare bankruptcy"
        case .acknowledge: return "OK"
        }
    }

    static func title(_ issue: Issue, in world: World) -> String {
        switch issue.kind {
        case .breakdown(let id): return "\(world.aircraft.first { $0.id == id }?.registration ?? "An aircraft") is broken down"
        case .overdraft: return "You are out of money"
        case .certificateReady(let level): return "You qualify for level \(level)"
        case .delivery(let id): return "\(world.aircraft.first { $0.id == id }?.registration ?? "An aircraft") has arrived"
        case .weather(let airport, _): return "Weather closes \(Place.name(airport))"
        case .bankruptcy: return "The airline has gone bankrupt"
        }
    }

    static func detail(_ issue: Issue, in world: World) -> String {
        switch issue.kind {
        case .breakdown: return "It cannot fly until it is repaired. A faster repair costs more."
        case .overdraft: return "Cash is below zero. Take a loan, sell something, or fly more profitable routes. Too many days like this ends the game."
        case .certificateReady: return "Open Money to buy the new certificate. It unlocks bigger aircraft and busier airports."
        case .delivery: return "Put it on a route from the Fleet screen."
        case .weather(_, let until): return "Flights wait until it reopens. It should clear by \(Format.date(GameClock(minute: until).date))."
        case .bankruptcy: return "The creditors have taken everything."
        }
    }
}
