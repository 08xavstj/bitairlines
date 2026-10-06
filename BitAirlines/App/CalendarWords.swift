import CoreCatalog
import CoreWorld

/// Words for the real-calendar features: the daily dispatch and its stamps, seasonal events, earned paint schemes,
/// the real-week goal and their news lines. Plain and specific, ASCII only.
enum CalendarWords {
    static func name(_ kind: SeasonKind) -> String {
        switch kind {
        case .newYearRush: "Lunar New Year"
        case .springBreak: "Spring break"
        case .summerPeak: "Summer peak"
        case .harvestFreight: "Harvest freight"
        case .festivalSeason: "Festival season"
        case .holidayParcels: "Holiday parcels"
        }
    }

    static func explain(_ kind: SeasonKind) -> String {
        switch kind {
        case .newYearRush: "Families travel home for the new year. More passengers on every route."
        case .springBreak: "School holidays. More people fly to the coast, to islands and to lakes."
        case .summerPeak: "The summer holidays. Busy flights to the coast, to islands and to lakes."
        case .harvestFreight: "Crops and supplies on the move. More freight on every route."
        case .festivalSeason: "Festivals and visits home. A few more passengers and a little more freight."
        case .holidayParcels: "Parcels and mail before the holidays. Much more freight on every route."
        }
    }

    /// The name of an earned paint scheme, or nil for any other livery name.
    static func liveryName(_ code: String) -> String? {
        switch code {
        case "classic.cheatline": return "Classic cheat line"
        case "classic.sunset": return "Sunset tail"
        case "classic.forest": return "Forest belly"
        case "classic.midnight": return "Midnight"
        case "classic.teal": return "Teal split"
        case "classic.polar": return "Polar stripe"
        default:
            let kind = SeasonKind.allCases.first { UnlockableLiveries.seasonCode($0) == code }
            return kind.map { name($0) + " scheme" }
        }
    }

    /// The extra tag on a job card: today's dispatch or a seasonal event's job.
    static func jobTag(_ job: Job) -> String? {
        if job.dispatchDay != nil { return "Today's dispatch" }
        if let season = job.season { return name(season) }
        return nil
    }

    static func stamps(_ n: Int) -> String { n == 1 ? "1 stamp" : "\(n) stamps" }

    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    /// A news line for the real-calendar milestones (nil for other milestones). Subjects are set in Core:
    /// "stamp:<total>", "stampreward:<livery code>", "season:<kind>", "seasonlivery:<kind>", "realgoal:<kind>:<airport>".
    static func news(_ item: NewsItem) -> String? {
        let parts = item.subject.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first, parts.count > 1 else { return nil }
        switch head {
        case "stamp":
            if item.amount >= Tuning.stampsPerReward { return "Dispatch flown: stamp \(parts[1]). That completes a card of \(Tuning.stampsPerReward)." }
            return "Dispatch flown: stamp \(parts[1]). \(stamps(item.amount)) more for the next reward."
        case "stampreward":
            let rare = item.amount > 0 ? " A rare find is waiting in the hangar." : ""
            guard let scheme = liveryName(parts[1]) else {
                return rare.isEmpty ? "Stamp reward: every classic paint scheme is already yours." : "Stamp reward:" + rare
            }
            return "Stamp reward: the \(scheme) paint scheme is yours. Paint it from the Logbook in the menu." + rare
        case "season":
            guard let kind = SeasonKind(rawValue: parts[1]) else { return nil }
            return "Event on: \(name(kind)), \(days(item.amount)) left. \(explain(kind)) Fly \(Tuning.seasonJobsForLivery) event jobs for its paint scheme."
        case "seasonlivery":
            guard let kind = SeasonKind(rawValue: parts[1]) else { return nil }
            return "\(Tuning.seasonJobsForLivery) \(name(kind).lowercased()) jobs flown: the \(name(kind)) scheme is yours. Paint it from the Logbook in the menu."
        case "realgoal":
            guard parts.count > 2 else { return nil }
            let what = parts[1] == WeeklyGoalKind.freightKg.rawValue ? "freight" : "passengers"
            return "Real-week goal met: \(what) to \(Place.name(parts[2])). Bonus of \(Format.dollars(item.amount)) paid."
        default:
            return nil
        }
    }
}
