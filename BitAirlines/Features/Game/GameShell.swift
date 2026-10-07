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
    /// The map's camera, open airport and route being planned, kept here so they are still there after a look at another screen.
    @State private var mapState: MapState
    /// The speed to go back to once the away summary or the perk choice closes (they cover the speed buttons, so the clock waits).
    @State private var heldSpeed: GameSpeed?

    init(session: GameSession, onExit: @escaping () -> Void, initialSection: GameSection = .map) {
        self.session = session
        self.onExit = onExit
        _section = State(initialValue: initialSection)
        _coach = State(initialValue: TutorialCoach(slot: session.slot))
        _mapState = State(initialValue: MapState(home: session.world.airline.home))
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
        .onChange(of: session.mapFocus) { _, focus in openMapIfAsked(focus) }
        .overlay(alignment: .bottom) { NoticeBanner(session: session) }
        .pixelConfirm("Leave the game?", message: "Your airline is saved. You can continue it from the title screen.", confirm: "Leave", isPresented: $confirmExit) { onExit() }
        .sheet(isPresented: $showMenu, onDismiss: { afterMenu?(); afterMenu = nil }) {
            GameMenu(session: session,
                     onAirline: { afterMenu = { section = .airline }; showMenu = false },
                     onSettings: { afterMenu = { showSettings = true }; showMenu = false },
                     onLeave: { afterMenu = { confirmExit = true }; showMenu = false })
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        // A decision is drawn over the game, so close the menu sheets that would hide it. The away summary and the perk choice
        // cover the speed buttons, so the clock waits while they are up. A watcher reads the world, so this body does not.
        .background {
            DecisionWatcher(session: session,
                            onDecision: { now in
                                if now {
                                    showMenu = false
                                    showSettings = false
                                }
                            },
                            onCoversClock: { covered in holdClock(covered) })
        }
    }

    /// Pauses the clock when a card covers the speed buttons, and goes back to the old speed when it closes.
    private func holdClock(_ covered: Bool) {
        if covered {
            guard session.speed != .paused else { return }
            heldSpeed = session.speed
            session.setSpeed(.paused)
        } else if let speed = heldSpeed {
            heldSpeed = nil
            session.setSpeed(speed)
        }
    }

    /// Opens the map when another screen asks it to show some airports.
    private func openMapIfAsked(_ focus: [String]?) {
        if focus != nil && section != .map { section = .map }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .map: MapScreen(session: session, map: mapState, guideRunning: coach.step != nil)
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

/// Watches the world for what needs the shell's attention, so the shell's own body does not read the world (it would be built
/// again on every clock tick). Draws nothing.
struct DecisionWatcher: View {
    let session: GameSession
    /// Called when something starts or stops waiting for the player: a stopping issue, a perk to pick, or the end of the game.
    let onDecision: (Bool) -> Void
    /// Called when a card that covers the speed buttons comes up or goes: the away summary or the perk choice. (A stopping
    /// issue already stops the clock in GameSession.)
    let onCoversClock: (Bool) -> Void

    var body: some View {
        let world = session.world
        let needs = world.isBankrupt || world.isPausedByIssue || !world.ops.perkChoices.isEmpty
        let covers = session.away != nil || !world.ops.perkChoices.isEmpty
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: needs) { _, now in onDecision(now) }
            .onChange(of: covers, initial: true) { _, now in onCoversClock(now) }
            .accessibilityHidden(true)
    }
}

struct TopBar: View {
    let session: GameSession
    let coach: TutorialCoach
    let onMenu: () -> Void
    @Environment(\.pixelStep) private var step

    /// The bar is one row of fixed controls, so its text grows one size at most. At the larger text sizes the row is wider
    /// than a 667 point phone, and MENU (the only way back to Settings) would be pushed off the screen.
    static let maxStep = 1

    var body: some View {
        let world = session.world
        HStack(spacing: 10) {
            Button { onMenu() } label: {
                VStack(spacing: 0) {
                    Text("MENU").pixelFont(8).foregroundStyle(Theme.textMuted)
                    Text(world.airline.code.uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 38)
                .background(PixelShape(step: 2).fill(Theme.surfaceRaised))
                .coachOutline(coach.step?.section == .airline)
            }
            .buttonStyle(.tap).accessibilityLabel("Menu")
            // MENU is never squeezed.
            .fixedSize()
            .layoutPriority(2)
            // When the row is tight the gap beside the speed buttons shrinks first, then the date (never MENU or the money).
            ClockLabel(clock: world.clock)
                .layoutPriority(0.5)
            SpeedControls(session: session, coach: coach)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 6) {
                    PayoutTag(payout: session.payout)
                    Text(Format.compactMoney(world.airline.cash)).pixelFont(13.333).foregroundStyle(world.airline.cash < 0 ? Theme.bad : Theme.good)
                        .lineLimit(1).fixedSize()
                }
                Text("Level \(world.airline.level)  Rep \(Int(world.airline.reputation))").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    .lineLimit(1).fixedSize()
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        // If the row is still too wide, it runs off the right edge, never the left, so MENU stays on the screen.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.panelBorder).frame(height: 2) }
        .environment(\.pixelStep, min(step, TopBar.maxStep))
    }
}

/// The date and time in the top bar. When there is room it keeps a steady width, so the speed buttons do not move as the
/// days go by; on a narrow screen it gives that room back first.
struct ClockLabel: View {
    let clock: GameClock

    var body: some View {
        ViewThatFits(in: .horizontal) {
            lines.frame(minWidth: 118, alignment: .leading)
            lines
        }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Format.date(clock.date)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Text("\(Format.weekdays[clock.weekday]) \(Format.time(clock))").pixelFont(10.667).foregroundStyle(Theme.textMuted).lineLimit(1)
        }
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
                    .frame(minWidth: 40, minHeight: 38)
                    .background(PixelShape(step: 2).fill(on ? Theme.accent : Theme.surfaceRaised))
                }
                .buttonStyle(.tap)
                .accessibilityLabel(speed == .paused ? "Pause" : "Speed \(speed.label)")
                .accessibilitySelected(on)
            }
        }
        .padding(.horizontal, 3).padding(.vertical, 2)
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
            VStack(spacing: 4) {
                ForEach(GameSection.rail) { s in
                    let on = s == section.railButton
                    Button { section = s } label: {
                        VStack(spacing: 1) {
                            PixelIconView(icon: s.icon, pixel: 2)
                            Text(s.title.uppercased()).pixelFont(8).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(on ? Theme.onAccent : Theme.textMuted)
                        .frame(width: 58, height: 40)
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
                .padding(16).frame(maxWidth: 520)
                .background(PixelPanel(fill: Theme.surface, border: Theme.accent.opacity(0.7)))
                .padding(.horizontal, 24).padding(.vertical, 8)
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
            if case .certificateReady = issue.kind { certificateButton }
            ForEach(issue.options, id: \.choice) { option in
                Button {
                    if option.choice == .declareBankruptcy { confirmingBankruptcy = true } else { session.resolve(issueID: issue.id, choice: option.choice) }
                } label: {
                    HStack {
                        Text(Messages.name(option, of: issue, in: session.world))
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

    /// On the 'you qualify' notice: buy the certificate here, or see what is missing. The notice's own choice only closes it.
    @ViewBuilder private var certificateButton: some View {
        let world = session.world
        if let next = world.nextLevelRequirement {
            Button {
                session.perform(sound: .coin) { try $0.upgradeCertificate() }
            } label: {
                HStack {
                    Text("Buy level \(next.level)")
                    Spacer()
                    Text(Format.dollars(next.fee))
                }
                .padding(.horizontal, 14)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!world.canUpgradeCertificate)
            if !world.canUpgradeCertificate && world.airline.cash < next.fee {
                Text("You need \(Format.dollars(next.fee - max(0, world.airline.cash))) more to buy it.")
                    .pixelFont(10.667).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, alignment: .leading)
            }
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

/// A line at the bottom of the screen when the game refuses something. Tap to close; it also goes by itself after a few seconds.
struct NoticeBanner: View {
    let session: GameSession
    static let showSeconds: UInt64 = 4

    var body: some View {
        if let notice = session.notice, !session.world.isPausedByIssue {
            Button { session.notice = nil } label: {
                Text(notice).pixelFont(10.667).foregroundStyle(Theme.onAccent)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .background(PixelShape(step: 2).fill(Theme.gold))
            }
            .buttonStyle(.tap)
            .frame(maxWidth: 560)
            .padding(.horizontal, 80).padding(.bottom, 8)
            .accessibilityLabel(notice)
            .task(id: notice) {
                try? await Task.sleep(nanoseconds: NoticeBanner.showSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                // Only clear the notice this banner showed, not a newer one.
                if session.notice == notice { session.notice = nil }
            }
        }
    }
}
