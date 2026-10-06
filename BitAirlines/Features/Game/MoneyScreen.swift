import SwiftUI
import CoreCatalog
import CoreWorld

/// Daily results as bars: green up for a profit, red down for a loss.
struct DailyBars: View {
    let books: [DayBook]

    var body: some View {
        let recent = Array(books.suffix(60))
        let biggest = max(1, recent.map { abs($0.net) }.max() ?? 1)
        Canvas { context, size in
            let mid = size.height / 2
            context.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Theme.panelBorder), style: FillStyle(antialiased: false))
            guard !recent.isEmpty else { return }
            let slot = size.width / 60
            for (i, day) in recent.enumerated() {
                let h = CGFloat(abs(day.net)) / CGFloat(biggest) * (mid - 2)
                let rect = day.net >= 0 ? CGRect(x: CGFloat(i) * slot, y: mid - h, width: max(1, slot - 1), height: h) : CGRect(x: CGFloat(i) * slot, y: mid, width: max(1, slot - 1), height: h)
                context.fill(Path(rect), with: .color(day.net >= 0 ? Theme.good : Theme.bad), style: FillStyle(antialiased: false))
            }
        }
        .frame(height: 64)
        .accessibilityLabel("Daily profit for the last 60 days")
    }
}

struct MoneyScreen: View {
    let session: GameSession
    @State private var loanAmount = 500_000.0

    var body: some View {
        let world = session.world
        let recent = world.books.suffix(30)
        let revenue = recent.reduce(0) { $0 + $1.revenue }
        let costs = recent.reduce(0) { $0 + $1.flightCosts + $1.overhead }
        let invested = recent.reduce(0) { $0 + $1.investments } + world.today.investments
        // Order: cash and result first, then goals and level, then the ways to spend, then loans and permits.
        Page {
            ScreenHeader("Money")
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CASH").pixelFont(8).foregroundStyle(Theme.textMuted)
                            Text(Format.dollars(world.airline.cash)).pixelFont(21.333).foregroundStyle(world.airline.cash < 0 ? Theme.bad : Theme.good).lineLimit(1).fixedSize()
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("RESULT, LAST 30 DAYS").pixelFont(8).foregroundStyle(Theme.textMuted)
                            Text(Format.signedMoney(revenue - costs)).pixelFont(16).foregroundStyle(revenue >= costs ? Theme.good : Theme.bad).lineLimit(1).fixedSize()
                        }
                    }
                    DailyBars(books: world.books)
                    KeyValueRow("Earned from flying", Format.compactMoney(revenue), color: Theme.good)
                    KeyValueRow("Running costs", Format.compactMoney(costs), color: Theme.bad)
                    KeyValueRow("Invested", Format.compactMoney(invested))
                    KeyValueRow("Pilot salaries", "\(Format.dollars(world.pilotPayroll)) a month")
                    KeyValueRow("Base upkeep", "\(Format.dollars(world.baseUpkeepPerDay)) a day")
                    Text("All for the last 30 days. Invested is what the airline keeps: aircraft, bases, kits, slots, training, permits and certificates. The result and the bars leave it out.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            SectionTitle("Goals and level")
            WeeklyGoalCard(world: world, session: session)
            DailyDispatchCard(world: world)
            SeasonCard(world: world)
            certificateCard(world)
            SectionTitle("Spending")
            SponsorCard(session: session)
            MarketingCard(session: session)
            StaffCard(session: session)
            FuelCard(session: session)
            SectionTitle("Loans")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(world.airline.loans) { loan in
                        HStack(spacing: 8) {
                            Text("\(Format.dollars(loan.remaining)) at \(Int((loan.annualRate * 100).rounded()))%, \(loan.monthsLeft) months left").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button("Repay") { session.perform(sound: .coin) { try $0.repayLoan(id: loan.id) } }.buttonStyle(.small).disabled(world.airline.cash < loan.remaining)
                        }
                    }
                    if world.airline.loans.isEmpty { Text("No loans.").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
                    let room = max(0, world.borrowingLimit - world.totalDebt)
                    let top = Double(max(100_000, room / 100_000 * 100_000))
                    let amount = Int(min(loanAmount, top))
                    PixelStepper(label: "Borrow", value: Binding(get: { min(loanAmount, top) }, set: { loanAmount = $0 }), range: 100_000...top, step: 100_000, display: { Format.compactMoney(Int($0)) })
                    Text("You can borrow up to \(Format.compactMoney(world.borrowingLimit)) in all; \(Format.compactMoney(room)) is left. Interest is 8.5% a year, paid back over five years.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    Button("Borrow \(Format.compactMoney(amount))") { session.perform(sound: .coin) { try $0.takeLoan(amount: amount) } }.buttonStyle(.smallProminent).disabled(room < 100_000)
                }
            }
            SectionTitle("Permits")
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You may fly in: " + world.airline.permits.map { CountryCatalog.country($0)?.name ?? $0 }.joined(separator: ", ")).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("Plan a route to another country on the Map and the game tells you the price of its permit.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func certificateCard(_ world: World) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("CERTIFICATE LEVEL \(world.airline.level)").pixelFont(13.333).foregroundStyle(Theme.accent)
                Text(Self.levelBlurb(world.airline.level)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if let next = world.nextLevelRequirement {
                    Text("To reach level \(next.level):").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                    StatBar(label: "Revenue", value: Double(min(world.airline.stats.revenue, next.lifetimeRevenue)), maximum: Double(next.lifetimeRevenue), color: Theme.info,
                            valueText: "\(Format.compactMoney(world.airline.stats.revenue)) of \(Format.compactMoney(next.lifetimeRevenue))")
                    StatBar(label: "Reputation", value: min(world.airline.reputation, next.reputation), maximum: next.reputation, color: Theme.gold,
                            valueText: "\(Int(world.airline.reputation)) of \(Int(next.reputation))")
                    Button("Buy level \(next.level) for \(Format.compactMoney(next.fee))") { session.perform { try $0.upgradeCertificate() } }.buttonStyle(.smallProminent).disabled(!world.canUpgradeCertificate)
                } else {
                    Text("You hold the highest certificate.").pixelFont(10.667).foregroundStyle(Theme.good)
                }
            }
        }
    }

    static func levelBlurb(_ level: Int) -> String {
        switch level {
        case 1: return "Bush operator: light aircraft and small towns."
        case 2: return "Commuter: bigger turboprops and towns of up to 400,000 people."
        case 3: return "Regional: regional airliners and cities of up to 1.5 million."
        case 4: return "Regional jets: big turboprops, jets and cities of up to 5 million."
        case 5: return "Mainline: narrowbody airliners and nearly every city."
        case 6: return "Widebody: long-haul airliners and the biggest hubs."
        default: return "Global carrier: jumbo jets everywhere."
        }
    }
}
