import SwiftUI
import CoreWorld

/// A strip under the top bar that tells a new player what to do next, and lights up the button to press. Gone once the guide is finished.
struct CoachStrip: View {
    let session: GameSession
    let coach: TutorialCoach
    @State private var suggestion: (code: String, perDay: Double)?

    var body: some View {
        if coach.active {
            // The guide follows the world: it looks at the step the world is on and tells the coach when that changes.
            let wanted = Tutorial.step(world: session.world, speed: session.speed, reviewed: false)
            strip
                .onChange(of: wanted, initial: true) { _, _ in coach.update(world: session.world, speed: session.speed) }
                .task { suggestion = Tutorial.suggestion(world: session.world) }
        }
    }

    @ViewBuilder private var strip: some View {
        if let step = coach.step {
            HStack(spacing: 10) {
                Tag(text: "Step \(step.rawValue + 1) of \(TutorialStep.allCases.count)", color: Theme.gold)
                Text(Tutorial.text(for: step, world: session.world, suggestion: suggestion, flights: session.world.airline.stats.flights))
                    .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if step == .review {
                    Button("Done") { coach.done() }.buttonStyle(.smallProminent)
                } else {
                    Button("Skip guide") { coach.finish() }.buttonStyle(.small)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surfaceRaised)
            .overlay(alignment: .top) { Rectangle().fill(Theme.gold).frame(height: 2) }
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// A gold outline round the control the guide wants pressed next.
    func coachOutline(_ lit: Bool) -> some View {
        overlay { if lit { PixelShape(step: 2).inset(by: 1).stroke(Theme.gold, lineWidth: 3).allowsHitTesting(false) } }
    }
}
