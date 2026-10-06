import SwiftUI

/// The studio screen shown when the app opens: the Lontra Industries logo dissolves in, "presents" appears, and the game moves on. Tap to skip.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    private static let total: Double = 4.3
    /// With Reduce Motion the logo is simply shown (no dissolve, no fade) and held a moment.
    private static let reducedTotal: Double = 2.4

    var body: some View {
        let total = reduceMotion ? Self.reducedTotal : Self.total
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            let reveal = reduceMotion ? 1 : min(1, max(0, (t - 0.25) / 1.6))
            let presents = t > (reduceMotion ? 0.6 : 2.6)
            let fade = !reduceMotion && t > total - 0.6 ? max(0, (total - t) / 0.6) : 1
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    // One art pixel is 4 by 5 device pixels (a third of a point per device pixel), so every block lands on whole screen pixels.
                    PixelArtView(art: LogoSprite.studio, pixel: 4.0 / 3.0, aspect: LogoSprite.aspect, reveal: reveal)
                    Text("PRESENTS").pixelFont(13.333).foregroundStyle(Theme.textMuted).opacity(presents ? 1 : 0)
                }
                .opacity(fade)
            }
            .onChange(of: t > total) { _, done in if done { finish() } }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear { start = Date() }
        .accessibilityLabel("Lontra Industries presents")
        .accessibilityAddTraits(.isButton)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
