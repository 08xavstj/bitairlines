import SwiftUI
import CoreWorld

/// After a certificate upgrade: pick one of three perks. Shown over the game until a choice is made.
struct PerkChoiceOverlay: View {
    let session: GameSession

    var body: some View {
        let choices = session.world.ops.perkChoices
        if !choices.isEmpty {
            ZStack {
                Color.black.opacity(0.62).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 10) {
                    Text("LEVEL \(session.world.airline.level): CHOOSE A PERK").pixelFont(16).foregroundStyle(Theme.gold)
                    Text("Your new certificate comes with one of these. It lasts for the rest of the game.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(choices, id: \.self) { perk in
                            Button { session.perform(sound: .levelUp) { try $0.choosePerk(perk) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(Words.name(perk).uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent)
                                    Text(Words.explain(perk)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Text("TAKE THIS").pixelFont(10.667).foregroundStyle(Theme.gold)
                                }
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                                .padding(10)
                                .background(PixelPanel(fill: Theme.surfaceRaised, border: Theme.accent.opacity(0.6)))
                            }
                            .buttonStyle(.tap)
                        }
                    }
                }
                .padding(16).frame(maxWidth: 640)
                .background(PixelPanel(fill: Theme.surface, border: Theme.gold.opacity(0.7)))
                .padding(24)
                .accessibilityAddTraits(.isModal)
            }
        }
    }
}
