import SwiftUI
import CoreWorld

/// The in-game menu behind the MENU button: the airline screen, settings, leaderboards and leaving.
struct GameMenu: View {
    let session: GameSession
    let onAirline: () -> Void
    let onSettings: () -> Void
    let onLeave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showLogbook = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader(title: session.world.airline.name) { Button("Close") { dismiss() }.buttonStyle(.small) }
            // Scrolls, so every button stays reachable with a larger text size.
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 10) {
                        Button("Airline") { onAirline() }.buttonStyle(PrimaryButtonStyle())
                        Button("Logbook") { showLogbook = true }.buttonStyle(SecondaryButtonStyle())
                        Button("Settings") { onSettings() }.buttonStyle(SecondaryButtonStyle())
                        if GameCenter.shared.isSignedIn {
                            Button("Leaderboards") { dismiss(); GameCenter.shared.showDashboard() }.buttonStyle(SecondaryButtonStyle())
                        }
                        Button("Save and leave") { onLeave() }.buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(width: 260)
                    VStack(alignment: .leading, spacing: 8) {
                        MenuNote(title: "Airline", text: "Your look, totals, certificate level and when the game stops.")
                        MenuNote(title: "Logbook", text: "Airports, aircraft types and paint schemes you have collected.")
                        MenuNote(title: "Saving", text: "Your game saves by itself.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
        }
        .padding(16)
        .screenBackground()
        .sheet(isPresented: $showLogbook) { LogbookScreen(session: session) }
    }
}

/// One line about a menu item: its name, then what it holds.
struct MenuNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
            Text(text).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
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
