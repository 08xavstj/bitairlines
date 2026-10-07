import SwiftUI
import CoreCatalog
import CoreWorld

/// The airline itself: its look (logo, colours, paint scheme), its totals, and how the game treats problems.
struct AirlineScreen: View {
    let session: GameSession
    @State private var showStats = true
    @State private var sharing = false

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 8) {
            ScreenHeader(title: world.airline.name) {
                HStack(spacing: 8) {
                    Button("Share") { sharing = true }.buttonStyle(.small)
                    PixelChoice(options: [(label: "Look", value: true), (label: "Totals", value: false)], selection: Binding(get: { !showStats }, set: { showStats = !$0 }))
                        .frame(width: 180)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
            if showStats {
                Page {
                    ScenarioCard(world: world)
                    totals(world)
                    ReputationCard(world: world)
                    RulesCard(world: world)
                    if world.airline.level >= GameSection.lateLevel { RankingsCard(world: world) }
                    pauseCard(world)
                }
            } else {
                BrandingEditor(branding: Binding(get: { session.world.airline.branding }, set: { value in session.world.setBranding(value) }), airlineName: world.airline.name)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .background(PixelBackdrop())
        .sheet(isPresented: $sharing) { ShareAirlineSheet(world: session.world) }
    }

    @ViewBuilder private func totals(_ world: World) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("TOTALS").pixelFont(13.333).foregroundStyle(Theme.accent)
                KeyValueRow("Home", AirportCatalog.airport(world.airline.home).map { $0.label } ?? world.airline.home)
                MoveHeadquartersButton(session: session)
                KeyValueRow("Flights flown", Format.number(world.airline.stats.flights))
                KeyValueRow("Passengers carried", Format.number(world.airline.stats.passengers))
                KeyValueRow("Freight carried", Format.number(world.airline.stats.cargoKg) + " kg")
                KeyValueRow("Total revenue", Format.compactMoney(world.airline.stats.revenue))
                KeyValueRow("Reputation", "\(Int(world.airline.reputation)) of 100")
                KeyValueRow("Fuel price", "\(Int((world.market.fuelIndex * 100).rounded()))% of normal")
            }
        }
    }

    @ViewBuilder private func pauseCard(_ world: World) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("WHEN TO STOP THE GAME").pixelFont(13.333).foregroundStyle(Theme.accent)
                Text("Your aircraft fly their routes on their own. The game stops when something needs you.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                PixelChoice(options: [(label: "Never", value: PausePolicy.never), (label: "Problems", value: PausePolicy.critical), (label: "Everything", value: PausePolicy.all)],
                            selection: Binding(get: { session.world.pausePolicy }, set: { session.world.setPausePolicy($0) }))
                Text(Self.explain(world.pausePolicy)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func explain(_ policy: PausePolicy) -> String {
        switch policy {
        case .never: return "Never stops, except when money runs out. Problems wait in your Inbox, and a broken aircraft stays grounded until you act."
        case .critical: return "Stops for breakdowns and for running out of money. Deliveries and weather go to the Inbox."
        case .all: return "Stops for everything, including deliveries and weather."
        }
    }
}
