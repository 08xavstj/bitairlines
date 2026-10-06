import SwiftUI
import CoreCatalog
import CoreWorld

extension Messages {
    /// One line of the news feed.
    static func news(_ item: NewsItem, in world: World) -> String {
        switch item.kind {
        case .routeOpened: return "New route opened: \(item.subject)."
        case .aircraftDelivered: return "\(item.subject) has arrived at \(Place.name(world.airline.home))."
        case .aircraftSold: return "\(item.subject) was sold for \(Format.dollars(item.amount))."
        case .certificate: return "You now hold certificate level \(item.amount)."
        case .breakdown: return "\(item.subject) broke down on the ground."
        case .weather: return "Weather closed \(Place.name(item.subject)) for a few days."
        case .loan: return item.subject == "taken" ? "You took a loan of \(Format.dollars(item.amount))." : "You repaid a loan of \(Format.dollars(item.amount))."
        case .permit: return "You bought a permit for \(CountryCatalog.country(item.subject)?.name ?? item.subject) (\(Format.dollars(item.amount)))."
        case .milestone:
            if item.subject.hasPrefix("rare:") { return rareFind(item) }
            if item.subject.hasPrefix("goal:") { return goalMet(item) }
            return item.subject
        case .perk: return "You took the \(Perk(rawValue: item.subject).map { Words.name($0) } ?? "new") perk."
        case .fuelBought: return "You bought \(Format.number(item.amount)) kg of fuel ahead."
        case .jobDone: return "Job done at \(Place.name(item.subject)): \(Format.dollars(item.amount))."
        case .jobLate: return "Job finished late at \(Place.name(item.subject)): half pay, \(Format.dollars(item.amount))."
        case .event:
            let kind = EventKind.allCases.indices.contains(item.amount) ? EventKind.allCases[item.amount] : .oilShock
            return Words.explain(kind, place: item.subject)
        case .baseBuilt:
            let facility = Facility.allCases.indices.contains(item.amount) ? Facility.allCases[item.amount] : .fuelDepot
            return "\(Words.name(facility)) built at \(Place.name(item.subject))."
        case .kitFitted:
            let kit = Kit.allCases.indices.contains(item.amount) ? Kit.allCases[item.amount] : .floats
            return "\(item.subject) is being fitted with \(Words.name(kit).lowercased())."
        case .slotBought: return "You bought \(item.amount) daily slot\(item.amount == 1 ? "" : "s") at \(Place.name(item.subject))."
        case .rivalRoute: return RivalWords.news(item, world: world)
        case .pilotHired: return "\(item.subject) joined as a pilot."
        case .pilotSick: return "\(item.subject) is off sick for a few days."
        case .noCrew: return "\(item.subject) is waiting for a pilot."
        case .scenario: return item.subject == "failed" ? "The scenario deadline passed." : "Scenario complete: \(item.subject) medal."
        }
    }

    /// A weekly goal was met. The subject is "goal:<kind>" or, for a place goal, "goal:<kind>:<airport>"; the amount the bonus.
    static func goalMet(_ item: NewsItem) -> String {
        let parts = item.subject.split(separator: ":").map(String.init)
        let bonus = "Bonus of \(Format.dollars(item.amount)) paid."
        guard parts.count > 2 else { return "Weekly goal met. " + bonus }
        let what = parts[1] == WeeklyGoalKind.freightKg.rawValue ? "freight" : "passengers"
        return "Weekly goal met: \(what) to \(Place.name(parts[2])). " + bonus
    }

    /// A rare find came up on the used market. The subject is "rare:<kind>:<type id>", the amount the price.
    static func rareFind(_ item: NewsItem) -> String {
        let parts = item.subject.split(separator: ":").map(String.init)
        let kind = parts.count > 1 ? RareFind(rawValue: parts[1]) : nil
        let model = parts.count > 2 ? AircraftCatalog.type(parts[2])?.displayName : nil
        let what = kind.map { ", " + Words.name($0).lowercased() } ?? ""
        let weeks = Tuning.rareFindDays / 7
        return "Rare find in the hangar: \(model ?? "a used aircraft")\(what), \(Format.dollars(item.amount)). On sale for \(weeks) week\(weeks == 1 ? "" : "s")."
    }
}

struct InboxScreen: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        Page {
            ScreenHeader("Inbox")
            if world.issues.isEmpty { EmptyNote("Nothing needs you right now.") }
            ForEach(world.issues) { issue in
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Messages.title(issue, in: world).uppercased()).pixelFont(13.333).foregroundStyle(issue.isCritical ? Theme.bad : Theme.accent).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        Text(Messages.detail(issue, in: world)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        IssueOptions(session: session, issue: issue)
                    }
                }
            }
            SectionTitle("News")
            ForEach(Array(world.news.reversed().enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(Format.date(GameClock(minute: item.minute).date)).pixelFont(10.667).foregroundStyle(Theme.textMuted).frame(width: 122, alignment: .leading)
                    Text(Messages.news(item, in: world)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if world.news.isEmpty { EmptyNote("No news yet.") }
        }
    }
}
