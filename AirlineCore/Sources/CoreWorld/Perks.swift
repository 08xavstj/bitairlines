// CoreWorld/Perks.swift: at each new certificate level the player picks one of three perks. Each one nudges a single number.
import CoreCatalog
import CoreSim

public enum Perk: String, Sendable, Hashable, Codable, CaseIterable {
    /// Fuel loaded at the home airport costs 15 percent less.
    case homeFuelDeal
    /// Turnarounds take a quarter less time.
    case quickTurns
    /// Reputation grows 30 percent faster.
    case goodName
    /// Maintenance costs 10 percent less and scheduled checks take half as long.
    case mechanicsGuild
    /// Operating permits cost half.
    case permitOffice
    /// Hiring and training pilots costs half.
    case pilotSchool
    /// Freight pays 10 percent more.
    case freightNetwork
    /// People choose the airline a little more often (5 percent more of every market).
    case knownFace
    /// Landing and passenger fees are a quarter lower at small strips and seaplane bases.
    case smallFieldDeal

    public static let choicesOffered = 3
}

extension World {
    public func has(_ perk: Perk) -> Bool { ops.perks.contains(perk) }

    /// Offers three perks the airline does not have yet (fewer when nearly all are taken).
    mutating func offerPerks() {
        var left = Perk.allCases.filter { !ops.perks.contains($0) }
        ops.rng.shuffle(&left)
        ops.perkChoices = Array(left.prefix(Perk.choicesOffered))
    }

    /// Takes one of the perks on offer.
    public mutating func choosePerk(_ perk: Perk) throws {
        guard ops.perkChoices.contains(perk) else { throw WorldError.invalidChoice }
        ops.perks.append(perk)
        ops.perkChoices = []
        addNews(.perk, subject: perk.rawValue, amount: airline.level)
    }

    // MARK: The numbers the perks change

    var turnaroundFactor: Double { has(.quickTurns) ? 0.75 : 1.0 }
    var reputationFactor: Double { has(.goodName) ? 1.3 : 1.0 }
    var maintenanceFactor: Double { has(.mechanicsGuild) ? 0.9 : 1.0 }
    var cargoRateFactor: Double { has(.freightNetwork) ? 1.1 : 1.0 }
    var captureFactor: Double { (has(.knownFace) ? 1.05 : 1.0) * marketingFactor }
    var pilotCostFactor: Double { has(.pilotSchool) ? 0.5 : 1.0 }

    /// What a permit for this country costs this airline.
    public func permitPrice(country: String) -> Int {
        let price = Progression.permitPrice(country: country)
        return has(.permitOffice) ? price / 2 : price
    }

    /// Turnaround in hours for an engine type, after perks.
    public func turnaroundHours(_ engine: EngineKind) -> Double { Tuning.turnaroundHours(engine) * turnaroundFactor }
}
