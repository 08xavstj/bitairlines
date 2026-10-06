import SwiftUI
import CoreWorld

enum AppScreen { case title, newGame, game }

/// Chooses between the title screen, the new-airline flow and a game in progress.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.audio) private var audio
    @Environment(\.scenePhase) private var scenePhase
    @State private var screen: AppScreen = .title
    @State private var session: GameSession?
    @State private var store = SaveStore(cloud: CloudSaves())
    @State private var firstSection: GameSection = .map
    @State private var firstStep = 0
    @State private var firstScenario: ScenarioID?
    /// When the app went to the background, so the fleet can catch up on return.
    @State private var backgroundedAt: Date?
    /// Whether the clock was running when the app went to the background (a paused game stays where it was).
    @State private var wasRunning = false
    /// Why a save could not be opened, shown on the title screen.
    @State private var loadProblem: String?

    var body: some View {
        ZStack {
            switch screen {
            case .title:
                TitleView(store: store, onNew: { screen = .newGame }, onContinue: { slot in continueGame(slot: slot) })
            case .newGame:
                // A scenario or step asked for once (the demo shortcuts) is not asked for again by the next New airline.
                NewGameFlow(store: store, onCancel: { firstScenario = nil; firstStep = 0; screen = .title },
                            onStart: { world, slot in firstScenario = nil; firstStep = 0; TutorialStore().setActive(true, slot: slot); begin(world: world, slot: slot) },
                            initialStep: firstStep, scenario: firstScenario)
            case .game:
                if let session {
                    GameShell(session: session, onExit: { leaveGame() }, initialSection: firstSection)
                        .overlay { NotificationAsk(session: session) }
                        .background { ReviewPromptWatcher(session: session) }
                }
            }
            if settings.scanlines { ScanlineOverlay() }
        }
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: screen, initial: true) { _, now in audio?.setMusic(now == .game ? .flying : .title) }
        // iOS may close a game in the background without warning, so save the moment the player leaves the app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if let session {
                    // Stop the clock too, so nothing happens between this save and iOS suspending the app.
                    wasRunning = session.speed != .paused
                    session.stop()
                    backgroundedAt = Date()
                }
                scheduleNotifications()
            } else if phase == .active {
                Notifier.cancelAll()
                if let since = backgroundedAt, let session {
                    backgroundedAt = nil
                    session.start()
                    if wasRunning { session.catchUp(realSeconds: Date().timeIntervalSince(since)) }
                }
            }
        }
        .pixelAlert("Cannot open this save", message: loadProblem, isPresented: Binding(get: { loadProblem != nil }, set: { if !$0 { loadProblem = nil } }))
        .onAppear {
            store.cloud?.enabled = { [settings] in settings.iCloudSaves }
            GameCenter.shared.signIn()
        }
        #if DEBUG
        .task { launchDemo() }
        #endif
    }

    #if DEBUG
    /// Screenshot shortcut: `-DemoScreen map|jobs|fleet|pilots|routes|bases|market|money|inbox|airline|issue|perks|planner|tutorial1...tutorial3|title|scenarios|new0...new5`.
    private func launchDemo() {
        guard let name = Demo.screen else { return }
        if name.hasPrefix("new"), let step = Int(name.dropFirst(3)) {
            firstStep = step
            screen = .newGame
            return
        }
        if name == "scenarios" {
            firstScenario = .freezeUp
            screen = .newGame
            return
        }
        guard name != "title" else { return }
        let demoSlot = SaveStore.slotCount
        let stage = name.hasPrefix("tutorial") ? Int(name.dropFirst(8)) : nil
        TutorialStore().setActive(stage != nil, slot: demoSlot)
        let made: World?
        if let stage { made = try? Demo.freshWorld(stage: stage) } else { made = try? Demo.world(issue: name == "issue") }
        guard let world = made else { return }
        let sectionName = ["issue": "map", "perks": "map", "pilots": "fleet"][name] ?? name
        firstSection = stage != nil ? (stage == 2 ? .fleet : .map) : (GameSection(rawValue: sectionName) ?? .map)
        let demo = GameSession(world: world, slot: demoSlot, store: SaveStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bitairlines-demo")))
        demo.start()
        demo.setSpeed(name == "issue" || stage != nil ? .paused : .x4)
        session = demo
        screen = .game
    }
    #endif

    /// Leaving the app: one note for the first thing that will need the player (only if the clock was running, since a paused
    /// game does not move while away), and the daily reminder if it is on. Nothing is asked of iOS from here.
    private func scheduleNotifications() {
        var note: AwayNote?
        if settings.askedAboutNotifications, settings.notifyAircraft, wasRunning, let session { note = AwayNotes.next(for: session.world) }
        guard note != nil || settings.notifyDaily else { return }
        Notifier.schedule(note, daily: settings.notifyDaily)
    }

    private func continueGame(slot: Int) {
        guard let world = try? store.load(slot: slot) else {
            loadProblem = "That save could not be opened. It may come from a newer version of the game."
            return
        }
        let savedAt = store.summary(slot: slot)?.savedAt
        begin(world: world, slot: slot)
        if let savedAt { session?.catchUp(realSeconds: Date().timeIntervalSince(savedAt)) }
    }

    private func begin(world: World, slot: Int) {
        let newSession = GameSession(world: world, slot: slot, store: store)
        newSession.save()
        newSession.start()
        session = newSession
        screen = .game
    }

    private func leaveGame() {
        session?.stop()
        session = nil
        screen = .title
    }
}
