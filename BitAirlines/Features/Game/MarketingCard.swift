import SwiftUI
import CoreWorld

/// Paid campaigns: what each does, what it costs, and how long the one running has left.
struct MarketingCard: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("MARKETING").pixelFont(13.333).foregroundStyle(Theme.accent)
                Text("A campaign wins you a bigger share of the people who fly while it runs, and makes every route better known at once.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if world.routes.isEmpty {
                    Text("Open a route first: a campaign needs somewhere to fly.").pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Campaign.allCases, id: \.self) { c in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MarketingCard.name(c).uppercased()).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            Text(MarketingCard.explain(c)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let running = world.activeCampaign(c) {
                            let left = running.untilDay - world.clock.dayIndex
                            Tag(text: "\(left) day\(left == 1 ? "" : "s") left", color: Theme.good)
                        } else {
                            Button("Start, \(Format.compactMoney(world.campaignPrice(c)))") { session.perform(sound: .coin) { try $0.startCampaign(c) } }
                                .buttonStyle(.smallProminent)
                                .disabled(world.campaignProblem(c) != nil)
                        }
                    }
                }
                RewardButton(session: session, kind: .freePosters)
            }
        }
    }

    static func name(_ c: Campaign) -> String {
        switch c {
        case .posters: "Posters and the local paper"
        case .radio: "Radio across the region"
        case .national: "National campaign"
        }
    }

    static func explain(_ c: Campaign) -> String {
        let share = Int(((Tuning.campaignCaptureBoost(c) - 1) * 100).rounded())
        let rep = Int(Tuning.campaignReputation(c))
        return "\(Tuning.campaignDays(c)) days, \(share)% more passengers" + (rep > 0 ? ", reputation +\(rep)." : ".")
    }
}

/// Staff who take chores off the player, with their monthly pay.
struct StaffCard: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("STAFF").pixelFont(13.333).foregroundStyle(Theme.accent)
                Text("Hire people to run parts of the airline for you. They are paid on the 1st of each month.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                ForEach(StaffRole.allCases, id: \.self) { role in
                    let hired = world.hasStaff(role)
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(StaffCard.name(role).uppercased() + (hired ? ", HIRED" : "")).pixelFont(10.667).foregroundStyle(hired ? Theme.good : Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(StaffCard.explain(role) + " \(Format.dollars(world.staffSalary(role))) a month.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if hired {
                            Button("Let go") { session.perform { try $0.dismiss(role) } }.buttonStyle(.small)
                        } else {
                            Button("Hire") { session.perform(sound: .coin) { try $0.hire(role) } }.buttonStyle(.smallProminent)
                        }
                    }
                }
            }
        }
    }

    static func name(_ role: StaffRole) -> String {
        switch role {
        case .revenueManager: "Revenue manager"
        case .operationsManager: "Operations manager"
        case .fleetPlanner: "Fleet planner"
        }
    }

    static func explain(_ role: StaffRole) -> String {
        switch role {
        case .revenueManager: "Every Monday raises fares on routes that fly full and lowers them where seats fly empty."
        case .operationsManager: "Settles breakdowns at once with the quickest repair you can pay for, so the game does not stop."
        case .fleetPlanner: "Every Monday puts parked aircraft on the route they suit best and sets each schedule to the suggested one."
        }
    }
}
