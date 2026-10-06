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
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(Words.name(perk).uppercased()).pixelFont(13.333).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
                                    Text(Words.explain(perk)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    // Looks like a button, so it is clear the whole card is one.
                                    Text("TAKE THIS").pixelFont(10.667).foregroundStyle(Theme.onAccent)
                                        .frame(maxWidth: .infinity, minHeight: 32)
                                        .background(PixelShape(step: 2).fill(Theme.accent))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(10)
                                .background(PixelPanel(fill: Theme.surfaceRaised, border: Theme.accent.opacity(0.6)))
                            }
                            .buttonStyle(.tap)
                            .accessibilityLabel("\(Words.name(perk)): \(Words.explain(perk))")
                            .accessibilityHint("Takes this perk for the rest of the game.")
                        }
                    }
                    // Cards as tall as the longest text, no taller: all three the same height.
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: 640)
                .background(PixelPanel(fill: Theme.surface, border: Theme.gold.opacity(0.7)))
                .padding(24)
                .accessibilityAddTraits(.isModal)
            }
        }
    }
}
