import SwiftUI
import CoreCatalog
import CoreWorld

enum GameSection: String, CaseIterable, Identifiable {
    case map, jobs, fleet, routes, bases, market, money, inbox, airline
    var id: String { rawValue }

    var icon: PixelIcon {
        switch self {
        case .map: .map
        case .jobs: .jobs
        case .fleet: .fleet
        case .routes: .routes
        case .bases: .base
        case .market: .hangar
        case .money: .money
        case .inbox: .inbox
        case .airline: .flag
        }
    }

    var title: String {
        switch self {
        case .map: "Map"
        case .jobs: "Jobs"
        case .fleet: "Fleet"
        case .routes: "Routes"
        case .bases: "Bases"
        case .market: "Hangar"
        case .money: "Money"
        case .inbox: "Inbox"
        case .airline: "Airline"
        }
    }

    /// The buttons on the rail. Jobs sit with Routes, Bases with Fleet, and the Airline screen is in the menu.
    static let rail: [GameSection] = [.map, .fleet, .routes, .market, .money, .inbox]

    /// The rail button a screen belongs to (nil for the Airline screen, which opens from the menu).
    var railButton: GameSection? {
        switch self {
        case .jobs: .routes
        case .bases: .fleet
        case .airline: nil
        default: self
        }
    }

    /// The level from which late-game screens show (slots, rival rankings, hub terminals).
    static let lateLevel = 3
}

/// A game in progress: top bar with the clock and money, a rail of screens, and the screen itself.
struct GameShell: View {
    let session: GameSession
    let onExit: () -> Void
    @State private var section: GameSection
    @State private var confirmExit = false
    @State private var showMenu = false
    @State private var showSettings = false
    /// What the menu asked for, done once its sheet has closed (two sheets cannot swap in one step).
    @State private var afterMenu: (() -> Void)?
    @State private var coach: TutorialCoach

    init(session: GameSession, onExit: @escaping () -> Void, initialSection: GameSection = .map) {
        self.session = session
        self.onExit = onExit
        _section = State(initialValue: initialSection)
        _coach = State(initialValue: TutorialCoach(slot: session.slot))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(session: session, coach: coach, onMenu: { showMenu = true })
            CoachStrip(session: session, coach: coach)
            HStack(spacing: 0) {
                Rail(session: session, coach: coach, section: $section)
                content
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .background { SoundWatcher(session: session) }
        .background { RealDaySync(session: session) }
        .overlay { PerkChoiceOverlay(session: session) }
        .overlay { IssueOverlay(session: session, onExit: onExit) }
        .overlay { AwaySummary(session: session) }
        .overlay(alignment: .bottom) { NoticeBanner(session: session) }
        .pixelConfirm("Leave the game?", message: "Your airline is saved. You can continue it from the title screen.", confirm: "Leave", isPresented: $confirmExit) { onExit() }
        .sheet(isPresented: $showMenu, onDismiss: { afterMenu?(); afterMenu = nil }) {
            GameMenu(session: session,
                     onAirline: { afterMenu = { section = .airline }; showMenu = false },
                     onSettings: { afterMenu = { showSettings = true }; showMenu = false },
                     onLeave: { afterMenu = { confirmExit = true }; showMenu = false })
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .map: MapScreen(session: session)
        case .jobs: SubTabs(first: .routes, second: .jobs, section: $section) { JobsScreen(session: session) }
        case .fleet: SubTabs(first: .fleet, second: .bases, section: $section) { FleetScreen(session: session) }
        case .routes: SubTabs(first: .routes, second: .jobs, section: $section) { RoutesScreen(session: session) }
        case .bases: SubTabs(first: .fleet, second: .bases, section: $section) { BasesScreen(session: session) }
        case .market: MarketScreen(session: session)
        case .money: MoneyScreen(session: session)
        case .inbox: InboxScreen(session: session)
        case .airline: AirlineScreen(session: session)
        }
    }
}

struct TopBar: View {
    let session: GameSession
    let coach: TutorialCoach
    let onMenu: () -> Void

    var body: some View {
        let world = session.world
        HStack(spacing: 10) {
            Button { onMenu() } label: {
                VStack(spacing: 0) {
                    Text("MENU").pixelFont(8).foregroundStyle(Theme.textMuted)
                    Text(world.airline.code.uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 8).frame(height: 34)
                .background(PixelShape(step: 2).fill(Theme.surfaceRaised))
                .coachOutline(coach.step?.section == .airline)
            }
            .buttonStyle(.tap).accessibilityLabel("Menu")
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.date(world.clock.date)).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                Text("\(Format.weekdays[world.clock.weekday]) \(Format.time(world.clock))").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }
            .frame(width: 122, alignment: .leading)
            SpeedControls(session: session, coach: coach)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 6) {
                    PayoutTag(payout: session.payout)
                    Text(Format.compactMoney(world.airline.cash)).pixelFont(13.333).foregroundStyle(world.airline.cash < 0 ? Theme.bad : Theme.good)
                }
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
    let coach: TutorialCoach

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
                .buttonStyle(.tap)
                .accessibilityLabel(speed == .paused ? "Pause" : "Speed \(speed.label)")
                .accessibilitySelected(on)
            }
        }
        .padding(3)
        .coachOutline(coach.step?.highlightsSpeed == true)
    }
}

struct Rail: View {
    let session: GameSession
    let coach: TutorialCoach
    @Binding var section: GameSection

    var body: some View {
        let waiting = session.world.issues.count
        ScrollView {
            VStack(spacing: 2) {
                ForEach(GameSection.rail) { s in
                    let on = s == section.railButton
                    Button { section = s } label: {
                        VStack(spacing: 1) {
                            PixelIconView(icon: s.icon, pixel: 2)
                            Text(s.title.uppercased()).pixelFont(8).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(on ? Theme.onAccent : Theme.textMuted)
                        .frame(width: 58, height: 34)
                        .background(PixelShape(step: 2).fill(on ? Theme.accent : Theme.surfaceRaised))
                        .overlay(alignment: .topTrailing) {
                            if s == .inbox && waiting > 0 {
                                Text("\(waiting)").pixelFont(8).foregroundStyle(Theme.onAccent).padding(.horizontal, 4).background(Theme.bad)
                            }
                        }
                        .coachOutline(coach.step?.section?.railButton == s && !on)
                    }
                    .buttonStyle(.tap)
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
    /// Bankruptcy ends the game, so it asks first.
    @State private var confirmingBankruptcy = false

    var body: some View {
        VStack(spacing: 8) {
            ForEach(issue.options, id: \.choice) { option in
                Button {
                    if option.choice == .declareBankruptcy { confirmingBankruptcy = true } else { session.resolve(issueID: issue.id, choice: option.choice) }
                } label: {
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
            if let kind = rewardKind { RewardButton(session: session, kind: kind, target: issue.id).frame(maxWidth: .infinity, alignment: .leading) }
            if let notice = session.notice { Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .pixelConfirm("Declare bankruptcy?", message: "The airline closes and this game ends. It cannot be undone.", confirm: "Close the airline", destructive: true,
                      isPresented: $confirmingBankruptcy) {
            session.resolve(issueID: issue.id, choice: .declareBankruptcy)
        }
    }

    /// The optional ad for this issue: the mechanic flies in free, or a sponsor helps with the overdraft.
    private var rewardKind: RewardKind? {
        switch issue.kind {
        case .breakdown: return .freeMechanic
        case .overdraft: return .overdraftSponsor
        default: return nil
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
            .buttonStyle(.tap)
            .padding(.bottom, 8)
            .accessibilityLabel(notice)
        }
    }
}
