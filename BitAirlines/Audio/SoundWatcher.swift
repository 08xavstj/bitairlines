import SwiftUI
import CoreWorld

/// Sits behind the game screen and plays a sound when the world does something worth hearing: a delivery, a new route, a problem. It watches in its own
/// view so the clock ticking does not redraw the whole screen.
struct SoundWatcher: View {
    let session: GameSession
    @Environment(\.audio) private var audio

    var body: some View {
        Color.clear
            .onAppear { session.audio = audio }
            .onChange(of: WorldHeard(session.world)) { old, _ in
                audio?.play(strongest: SoundCues.between(old, and: session.world))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
