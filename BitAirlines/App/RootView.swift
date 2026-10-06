import SwiftUI
import CoreWorld

enum AppScreen { case title, newGame, game }

/// Chooses between the title screen, the new-airline flow and a game in progress.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var screen: AppScreen = .title
    @State private var session: GameSession?
    @State private var store = SaveStore()

    var body: some View {
        ZStack {
            switch screen {
            case .title:
                TitleView(store: store, onNew: { screen = .newGame }, onContinue: { slot in continueGame(slot: slot) })
            case .newGame:
                NewGameFlow(store: store, onCancel: { screen = .title }, onStart: { world, slot in begin(world: world, slot: slot) })
            case .game:
                if let session {
                    GameShell(session: session, onExit: { leaveGame() })
                }
            }
            if settings.scanlines { ScanlineOverlay() }
        }
        .background(Theme.background.ignoresSafeArea())
    }

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
