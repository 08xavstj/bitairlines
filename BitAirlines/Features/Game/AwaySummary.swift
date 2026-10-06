import SwiftUI
import CoreWorld

/// "While you were away": what the fleet did during a break, shown once when the player comes back.
struct AwaySummary: View {
    let session: GameSession

    var body: some View {
        if let report = session.away, !session.world.isBankrupt {
            ZStack {
                Color.black.opacity(0.62).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHILE YOU WERE AWAY").pixelFont(16).foregroundStyle(Theme.accent)
                    Text("\(Format.wait(minutes: report.gameMinutes)) of flying went by.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    KeyValueRow("Flights", Format.number(report.flights))
                    KeyValueRow("Passengers", Format.number(report.passengers))
                    KeyValueRow("Earned from flights", Format.dollars(report.revenue))
                    KeyValueRow("Cash change", Format.signedMoney(report.cashChange))
                    if report.stoppedForIssue {
                        Text("Something needs you, so the clock stopped early.").pixelFont(10.667).foregroundStyle(Theme.gold)
                    }
                    Button("Back to work") { session.away = nil }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(16).frame(maxWidth: 420)
                .background(PixelPanel(fill: Theme.surface, border: Theme.accent.opacity(0.7)))
                .padding(24)
            }
        }
    }
}
