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

    var body: some View {
        ZStack {
            switch screen {
            case .title:
                TitleView(store: store, onNew: { screen = .newGame }, onContinue: { slot in continueGame(slot: slot) })
            case .newGame:
                NewGameFlow(store: store, onCancel: { screen = .title }, onStart: { world, slot in begin(world: world, slot: slot) }, initialStep: firstStep)
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
    /// Screenshot shortcut: `-DemoScreen map|fleet|routes|market|money|inbox|airline|issue|title|new0...new4`.
    private func launchDemo() {
        guard let name = Demo.screen else { return }
        if name.hasPrefix("new"), let step = Int(name.dropFirst(3)) {
            firstStep = step
            screen = .newGame
            return
        }
        guard name != "title" else { return }
        guard let world = try? Demo.world(issue: name == "issue") else { return }
        firstSection = GameSection(rawValue: name == "issue" ? "map" : name) ?? .map
        let demo = GameSession(world: world, slot: SaveStore.slotCount, store: SaveStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bitairlines-demo")))
        demo.start()
        demo.setSpeed(name == "issue" ? .paused : .x4)
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
