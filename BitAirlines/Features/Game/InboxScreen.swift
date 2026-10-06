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
        case .milestone: return item.subject
        }
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
