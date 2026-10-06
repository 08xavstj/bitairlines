import SwiftUI
import CoreWorld

/// The in-game menu behind the MENU button: the airline screen, settings, leaderboards and leaving.
struct GameMenu: View {
    let session: GameSession
    let onAirline: () -> Void
    let onSettings: () -> Void
    let onLeave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader(title: session.world.airline.name) { Button("Close") { dismiss() }.buttonStyle(.small) }
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    Button("Airline") { onAirline() }.buttonStyle(PrimaryButtonStyle())
                    Button("Settings") { onSettings() }.buttonStyle(SecondaryButtonStyle())
                    if GameCenter.shared.isSignedIn {
                        Button("Leaderboards") { dismiss(); GameCenter.shared.showDashboard() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Save and leave") { onLeave() }.buttonStyle(SecondaryButtonStyle())
                }
                .frame(width: 260)
                Text("Airline has your look, totals, level and what makes the game stop. Your game saves by itself.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
    }
}

/// Two screens that share one rail button, with a switch at the top (Routes and Jobs, Fleet and Bases).
struct SubTabs<Content: View>: View {
    let first: GameSection
    let second: GameSection
    @Binding var section: GameSection
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            PixelChoice(options: [(label: first.title, value: first), (label: second.title, value: second)], selection: $section)
                .frame(maxWidth: 320)
                .padding(.horizontal, 12).padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }
}
