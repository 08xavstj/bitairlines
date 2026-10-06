import SwiftUI
import CoreWorld

enum AppScreen { case title, newGame, game }

/// Chooses between the title screen, the new-airline flow and a game in progress.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.audio) private var audio
    @State private var screen: AppScreen = .title
    @State private var session: GameSession?
    @State private var store = SaveStore()
    @State private var firstSection: GameSection = .map
    @State private var firstStep = 0
    @State private var firstScenario: ScenarioID?

    var body: some View {
        ZStack {
            switch screen {
            case .title:
                TitleView(store: store, onNew: { screen = .newGame }, onContinue: { slot in continueGame(slot: slot) })
            case .newGame:
                NewGameFlow(store: store, onCancel: { screen = .title }, onStart: { world, slot in TutorialStore().setActive(true, slot: slot); begin(world: world, slot: slot) }, initialStep: firstStep,
                            scenario: firstScenario)
            case .game:
                if let session {
                    GameShell(session: session, onExit: { leaveGame() }, initialSection: firstSection)
                }
            }
            if settings.scanlines { ScanlineOverlay() }
        }
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: screen, initial: true) { _, now in audio?.setMusic(now == .game ? .flying : .title) }
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

    private func continueGame(slot: Int) {
        guard let world = try? store.load(slot: slot) else { return }
        begin(world: world, slot: slot)
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
