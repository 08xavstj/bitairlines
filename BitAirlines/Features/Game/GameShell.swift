import SwiftUI
import CoreCatalog
import CoreWorld

enum GameSection: String, CaseIterable, Identifiable {
    case map, fleet, routes, market, money, inbox, airline
    var id: String { rawValue }

    var icon: PixelIcon {
        switch self {
        case .map: .map
        case .fleet: .fleet
        case .routes: .routes
        case .market: .hangar
        case .money: .money
        case .inbox: .inbox
        case .airline: .flag
        }
    }

    var title: String {
        switch self {
        case .map: "Map"
        case .fleet: "Fleet"
        case .routes: "Routes"
        case .market: "Hangar"
        case .money: "Money"
        case .inbox: "Inbox"
        case .airline: "Airline"
        }
    }
}

/// A game in progress: top bar with the clock and money, a rail of screens, and the screen itself.
struct GameShell: View {
    let session: GameSession
    let onExit: () -> Void
    @State private var section: GameSection
    @State private var confirmExit = false

    init(session: GameSession, onExit: @escaping () -> Void, initialSection: GameSection = .map) {
        self.session = session
        self.onExit = onExit
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(session: session, onMenu: { confirmExit = true })
            HStack(spacing: 0) {
                Rail(session: session, section: $section)
                content
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay { IssueOverlay(session: session, onExit: onExit) }
        .overlay(alignment: .bottom) { NoticeBanner(session: session) }
        .pixelConfirm("Leave the game?", message: "Your airline is saved. You can continue it from the title screen.", confirm: "Leave", isPresented: $confirmExit) { onExit() }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .map: MapScreen(session: session)
        case .fleet: FleetScreen(session: session)
        case .routes: RoutesScreen(session: session)
        case .market: MarketScreen(session: session)
        case .money: MoneyScreen(session: session)
        case .inbox: InboxScreen(session: session)
        case .airline: AirlineScreen(session: session)
        }
    }
}

struct TopBar: View {
    let session: GameSession
    let onMenu: () -> Void

    var body: some View {
        let world = session.world
        HStack(spacing: 10) {
            Button { onMenu() } label: {
                Text(world.airline.code.uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent).padding(.horizontal, 8).frame(height: 32)
                    .background(PixelShape(step: 2).fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain).accessibilityLabel("Menu")
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.date(world.clock.date)).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                Text("\(Format.weekdays[world.clock.weekday]) \(Format.time(world.clock))").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }
            .frame(width: 122, alignment: .leading)
            SpeedControls(session: session)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.compactMoney(world.airline.cash)).pixelFont(13.333).foregroundStyle(world.airline.cash < 0 ? Theme.bad : Theme.good)
                Text("Level \(world.airline.level)  Rep \(Int(world.airline.reputation))").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 2) }
    }
}

struct SpeedControls: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GameSpeed.allCases) { speed in
                let on = session.speed == speed
                Button { session.setSpeed(speed) } label: {
                    Group {
                        if speed == .paused { PixelIconView(icon: .pause, pixel: 2) } else { Text(speed.label).pixelFont(10.667) }
                    }
                    .foregroundStyle(on ? Theme.onAccent : Theme.textPrimary)
                    .frame(minWidth: 34, minHeight: 32)
                    .background(PixelShape(step: 2).fill(on ? Theme.accent : Theme.surfaceRaised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speed == .paused ? "Pause" : "Speed \(speed.label)")
                .accessibilitySelected(on)
            }
        }
    }
}

struct Rail: View {
    let session: GameSession
    @Binding var section: GameSection

    var body: some View {
        let waiting = session.world.issues.count
        ScrollView {
            VStack(spacing: 3) {
                ForEach(GameSection.allCases) { s in
                    let on = s == section
                    Button { section = s } label: {
                        VStack(spacing: 2) {
                            PixelIconView(icon: s.icon, pixel: 2)
                            Text(s.title.uppercased()).pixelFont(8).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(on ? Theme.onAccent : Theme.textMuted)
                        .frame(width: 58, height: 41)
                        .background(PixelShape(step: 2).fill(on ? Theme.accent : Theme.surfaceRaised))
                        .overlay(alignment: .topTrailing) {
                            if s == .inbox && waiting > 0 {
                                Text("\(waiting)").pixelFont(8).foregroundStyle(Theme.onAccent).padding(.horizontal, 4).background(Theme.bad)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.title)
                    .accessibilitySelected(on)
                }
            }
            .padding(.vertical, 4).padding(.horizontal, 4)
        }
        .frame(width: 66)
        .background(Theme.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.panelBorder).frame(width: 2) }
    }
}

/// Shows a problem that stops the game, or the end of the game, over everything else.
struct IssueOverlay: View {
    let session: GameSession
    let onExit: () -> Void

    var body: some View {
        let world = session.world
        if world.isBankrupt {
            dialog {
                Text("GAME OVER").pixelFont(21.333).foregroundStyle(Theme.bad)
                Text("\(world.airline.name) has gone bankrupt. You flew \(Format.number(world.airline.stats.flights)) flights and carried \(Format.number(world.airline.stats.passengers)) passengers.")
                    .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Button("Back to the title") { onExit() }.buttonStyle(PrimaryButtonStyle())
            }
        } else if let issue = world.issues.first(where: { $0.pausesGame }) {
            dialog {
                Text(Messages.title(issue, in: world).uppercased()).pixelFont(16).foregroundStyle(issue.isCritical ? Theme.bad : Theme.accent).fixedSize(horizontal: false, vertical: true)
                Text(Messages.detail(issue, in: world)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                IssueOptions(session: session, issue: issue)
            }
        }
    }

    private func dialog<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(16).frame(maxWidth: 480)
                .background(PixelPanel(fill: Theme.surface, border: Theme.accent.opacity(0.7)))
                .padding(24)
        }
    }
}

/// The choices for one issue, as buttons with their cost.
struct IssueOptions: View {
    let session: GameSession
    let issue: Issue

    var body: some View {
        VStack(spacing: 8) {
            ForEach(issue.options, id: \.choice) { option in
                Button { session.resolve(issueID: issue.id, choice: option.choice) } label: {
                    HStack {
                        Text(Messages.name(option.choice))
                        Spacer()
                        if option.costUSD > 0 { Text(Format.dollars(option.costUSD)) }
                        if option.days > 0 { Text("\(option.days) day\(option.days == 1 ? "" : "s")") }
                    }
                    .padding(.horizontal, 14)
                }
                .buttonStyle(AnyButtonStyle(option.choice == .declareBankruptcy ? AnyButtonStyle(DangerWideButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle())))
            }
            if let notice = session.notice { Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
}

/// A line at the bottom of the screen when the game refuses something.
struct NoticeBanner: View {
    let session: GameSession

    var body: some View {
        if let notice = session.notice, !session.world.isPausedByIssue {
            Button { session.notice = nil } label: {
                Text(notice).pixelFont(10.667).foregroundStyle(Theme.onAccent).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(PixelShape(step: 2).fill(Theme.gold))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .accessibilityLabel(notice)
        }
    }
}
