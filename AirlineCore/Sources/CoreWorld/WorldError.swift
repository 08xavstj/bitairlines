// CoreWorld/WorldError.swift: why a player action was refused. The app turns these into messages.

public enum WorldError: Error, Sendable, Hashable {
    case unknownAirport(String)
    case unknownType(String)
    case unknownAircraft(Int)
    case unknownRoute(Int)
    case unknownListing(Int)
    case unknownIssue(Int)
    case notEnoughCash(needed: Int)
    case levelTooLow(required: Int)
    case airportLevelTooHigh(airport: String, required: Int)
    case permitRequired(country: String, price: Int)
    case routeNeedsTwoStops
    case tooManyStops
    case duplicateStops
    case aircraftCannotUse(airport: String)
    case outOfRange(km: Int)
    case notDelivered
    case aircraftBusy
    case aircraftHasRoute
    case notInProduction
    case invalidChoice
    case requirementsNotMet
    case alreadyHasPermit
    case invalidAmount
    case fuelStorageFull(capacityKg: Int)
    /// Realism: a stretch of the route between fuel stops is longer than the aircraft can fly.
    case noFuel(airport: String)
    case alreadyBuilt
    /// Marketing and staff.
    case campaignRunning
    case needsARoute
    case alreadyHired
    case notHired
    case cannotBuildHere
    case kitDoesNotFit
    case jobUnavailable
    case notEnoughRoom
}
