import SwiftUI
import CoreWorld

/// The title screen: the game's name, a plane crossing the night sky, and the way in.
struct TitleView: View {
    let store: SaveStore
    let onNew: () -> Void
    let onContinue: (Int) -> Void
    @State private var saves: [SaveSummary] = []
    @State private var showContinue = false
    @State private var showCredits = false
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Sky(reduceMotion: reduceMotion)
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PIXEL").pixelFont(48).foregroundStyle(Theme.textPrimary)
                    Text("PROPS").pixelFont(32).foregroundStyle(Theme.accent)
                    Text("Grow one small plane into a world airline.").pixelFont(10.667).foregroundStyle(Theme.textMuted).padding(.top, 6)
                }
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    if !saves.isEmpty { Button("Continue") { showContinue = true }.buttonStyle(PrimaryButtonStyle()) }
                    // Airlines in iCloud that found no free slot here (SaveSync: SyncReport.notBroughtIn).
                    let waiting = store.lastSync.notBroughtIn.count
                    if waiting > 0 {
                        Text(waiting == 1 ? "One more airline is in iCloud. Delete one here to bring it in."
                                          : "\(waiting) more airlines are in iCloud. Delete some here to bring them in.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("New airline") { onNew() }.buttonStyle(saves.isEmpty ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
                    HStack(spacing: 10) {
                        Button("Settings") { showSettings = true }.buttonStyle(SecondaryButtonStyle())
                        Button("Credits") { showCredits = true }.buttonStyle(SecondaryButtonStyle())
                    }
                    if GameCenter.shared.isSignedIn {
                        Button("Leaderboards") { GameCenter.shared.showDashboard() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                .frame(width: 260)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            saves = store.summaries()
            // A game played on another device arrives through iCloud; show it once it is here.
            store.syncWithCloud { saves = store.summaries() }
        }
        // RootView syncs with iCloud on every return to the front; read the saves again too.
        .onChange(of: scenePhase) { _, phase in if phase == .active { saves = store.summaries() } }
        .sheet(isPresented: $showContinue) { ContinueSheet(store: store, saves: $saves) { slot in showContinue = false; onContinue(slot) } }
        .sheet(isPresented: $showCredits) { CreditsView() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }
}

/// Stars, drifting clouds and a plane, drawn with blocks.
struct Sky: View {
    let reduceMotion: Bool

    private static let stars: [(x: Double, y: Double, size: CGFloat, phase: Double)] = (0..<70).map { i in
        let a = Double((i * 7919) % 1000) / 1000
        let b = Double((i * 104729) % 1000) / 1000
        return (x: a, y: b * 0.8, size: CGFloat(i % 9 == 0 ? 3 : 2), phase: Double(i % 7))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0)) { timeline in
            let t: Double = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    Canvas { context, size in
                        for star in Self.stars {
                            let blink = (t + star.phase).truncatingRemainder(dividingBy: 2.0) < 1.0 ? 1.0 : 0.4
                            let twinkle = reduceMotion ? 1.0 : 0.55 + 0.45 * blink
                            let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)
                            context.fill(Path(rect), with: .color(Theme.textPrimary.opacity(0.7 * twinkle)), style: FillStyle(antialiased: false))
                        }
                        let span = size.width + 200
                        for (i, row) in [0.30, 0.55, 0.72].enumerated() {
                            let speed = 6.0 * (1 + Double(i) * 0.4)
                            let x = (size.width - CGFloat(t * speed) + CGFloat(i) * 150).truncatingRemainder(dividingBy: span)
                            let wrapped = (x < 0 ? x + span : x) - 100
                            let y = size.height * row
                            context.fill(Path(CGRect(x: wrapped, y: y, width: 96, height: 10)), with: .color(Theme.surfaceRaised), style: FillStyle(antialiased: false))
                            context.fill(Path(CGRect(x: wrapped + 18, y: y - 10, width: 52, height: 10)), with: .color(Theme.surfaceRaised), style: FillStyle(antialiased: false))
                        }
                    }
                    let progress: Double = reduceMotion ? 0.55 : (t / 22).truncatingRemainder(dividingBy: 1.0)
                    let planeX: CGFloat = -160 + (geo.size.width + 320) * CGFloat(progress)
                    let bob: CGFloat = CGFloat(sin(t * 1.3)) * 4
                    AircraftSpriteView(family: .narrowbody, branding: .starter, pixel: 3).position(x: planeX, y: geo.size.height * 0.2 + bob)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct ContinueSheet: View {
    let store: SaveStore
    @Binding var saves: [SaveSummary]
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    /// The save waiting for "Delete" to be confirmed.
    @State private var deleting: SaveSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Continue") { Button("Close") { dismiss() }.buttonStyle(.small) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(saves) { save in
                        // A newer copy in iCloud needs a newer version of the game: playing this one would fork it (RootView refuses too).
                        let needsUpdate = !store.lastSync.needsUpdate.isEmpty && store.lastSync.needsUpdate.contains(store.gameID(slot: save.slot))
                        Card {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(save.airlineName.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                                    if needsUpdate {
                                        Text("Needs a newer version of Pixel Props: a newer copy of this airline is in iCloud.").pixelFont(10.667).foregroundStyle(Theme.gold)
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else if let date = save.date {
                                        Text("\(Format.date(date)) - \(Format.compactMoney(save.cash)) - \(save.aircraft) aircraft - level \(save.level)")
                                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text("This save was made by a newer version of the game, or is damaged.").pixelFont(10.667).foregroundStyle(Theme.bad)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 8)
                                Button("Delete") { deleting = save }.buttonStyle(.smallDanger)
                                if !save.broken && !needsUpdate { Button("Play") { onPick(save.slot) }.buttonStyle(.smallProminent) }
                            }
                        }
                    }
                    if saves.isEmpty { EmptyNote("No saved airlines. Start one with New airline on the title screen.") }
                }
            }
        }
        .padding(16)
        .screenBackground()
        .pixelConfirm("Delete \(deleting?.airlineName ?? "this airline")?", message: deleteMessage, confirm: "Delete",
                      destructive: true, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let save = deleting { store.delete(slot: save.slot) }
            deleting = nil
            saves = store.summaries()
        }
    }

    /// With iCloud saves off, the copy there goes the next time they are kept there (SaveStore remembers the deletion).
    private var deleteMessage: String {
        if store.cloud?.enabled == false {
            return "The save is gone for good from this device. It will be removed from iCloud the next time saves are kept there."
        }
        return "The save is gone for good from this device, and from iCloud if saves are kept there."
    }
}

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Credits") { Button("Close") { dismiss() }.buttonStyle(.small) }
            ScrollView {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A Lontra Industries game.").pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                        Text("Airports and runways: OurAirports, public domain.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text("Places and populations: GeoNames (geonames.org), CC BY 4.0.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text("Coastlines: Natural Earth, public domain.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text("All airlines are made up. Aircraft figures are rounded for play, not for flying.").pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text("Aircraft maker and model names belong to their owners. Pixel Props is not made with or endorsed by them.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        PrivacyPolicyButton()
                    }
                }
            }
        }
        .padding(16)
        .screenBackground()
    }
}

struct SettingsSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Settings") { Button("Close") { dismiss() }.buttonStyle(.small) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $settings.scanlines) { Text("CRT scanlines").pixelFont(13.333).foregroundStyle(Theme.textPrimary) }.toggleStyle(PixelToggleStyle())
                            Toggle(isOn: $settings.haptics) { Text("Vibration").pixelFont(13.333).foregroundStyle(Theme.textPrimary) }.toggleStyle(PixelToggleStyle())
                            Toggle(isOn: $settings.soundEffects) { Text("Sound effects").pixelFont(13.333).foregroundStyle(Theme.textPrimary) }.toggleStyle(PixelToggleStyle())
                            Toggle(isOn: $settings.music) { Text("Music").pixelFont(13.333).foregroundStyle(Theme.textPrimary) }.toggleStyle(PixelToggleStyle())
                            Toggle(isOn: $settings.iCloudSaves) { Text("Keep saves in iCloud").pixelFont(13.333).foregroundStyle(Theme.textPrimary) }.toggleStyle(PixelToggleStyle())
                            Text("Copies each airline to your iCloud, so it follows you to another iPhone or iPad with the same Apple Account. Needs iCloud Drive on in the iPhone Settings app. Saves always stay on this phone too.")
                                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                            Toggle(isOn: aircraftNotes) { Text("Tell me when an aircraft needs me").pixelFont(13.333).foregroundStyle(Theme.textPrimary) }.toggleStyle(PixelToggleStyle())
                            Toggle(isOn: dailyNotes) { Text("Remind me of the daily dispatch").pixelFont(13.333).foregroundStyle(Theme.textPrimary) }.toggleStyle(PixelToggleStyle())
                            Text("Notes arrive only while you are away from the game, at most two at a time. If none arrive, allow notifications for the game in the iPhone Settings app.")
                                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                            Text("Volume").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            PixelChoice(options: VolumeLevel.allCases.map { (label: $0.label, value: $0) }, selection: $settings.volume)
                            Text("Text size").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            PixelChoice(options: TextSize.allCases.map { (label: $0.label, value: $0) }, selection: $settings.textSize)
                        }
                    }
                    PrivacyCard()
                }
            }
        }
        .padding(16)
        .screenBackground()
    }

    /// On only once the player has been asked and said yes (the event note is never sent before that).
    private var aircraftNotes: Binding<Bool> {
        Binding(get: { settings.askedAboutNotifications && settings.notifyAircraft }, set: { on in
            settings.notifyAircraft = on
            if on { askSystem(ifRefused: { settings.notifyAircraft = false }) }
        })
    }

    private var dailyNotes: Binding<Bool> {
        Binding(get: { settings.notifyDaily }, set: { on in
            settings.notifyDaily = on
            if on { askSystem(ifRefused: { settings.notifyDaily = false }) }
        })
    }

    /// Turning a note on asks iOS for permission (the system asks only once; later answers come straight back). A no turns it off again.
    private func askSystem(ifRefused turnOff: @escaping @MainActor () -> Void) {
        settings.askedAboutNotifications = true
        Notifier.requestPermission { granted in if !granted { turnOff() } }
    }
}
