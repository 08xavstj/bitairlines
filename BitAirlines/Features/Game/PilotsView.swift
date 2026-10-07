import SwiftUI
import CoreCatalog
import CoreWorld

/// The pilots: who flies what, who is off sick or on a course, the pilots looking for work, and automatic hiring.
/// A Group, not a stack: the rows sit straight in the Fleet page's lazy list, so only the ones on screen are built.
struct PilotsView: View {
    let session: GameSession
    @State private var training: Int?

    var body: some View {
        let world = session.world
        let now = world.clock.minute
        // Each pilot's aircraft by id, looked up once for the whole list instead of a search of the fleet per pilot.
        let registrations = PilotsView.registrationsByID(world)
        Group {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    KeyValueRow("Pilots", "\(world.ops.pilots.count)")
                    KeyValueRow("Salaries", "\(Format.dollars(world.pilotPayroll)) a month")
                    Toggle(isOn: Binding(get: { session.world.ops.autoHirePilots }, set: { v in session.perform { $0.setAutoHire(v) } })) {
                        Text("Hire pilots automatically for new aircraft").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }.toggleStyle(PixelToggleStyle())
                }
            }
            // The sheet hangs off the card at the top (always on screen), not off every row.
            .sheet(item: Binding(get: { training.map { SheetID(id: $0) } }, set: { training = $0?.id })) { sheet in
                TrainingSheet(session: session, pilotID: sheet.id)
            }
            // A stopping issue is drawn under any sheet: close the sheet so the player sees it.
            .onChange(of: session.world.isPausedByIssue) { _, now in if now { training = nil } }
            SectionTitle("Your pilots")
            if world.ops.pilots.isEmpty {
                EmptyNote("No pilots yet. Hire one below, or turn on automatic hiring above.")
            }
            ForEach(world.ops.pilots) { pilot in
                let spare = world.isSpare(pilot)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pilot.name.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(pilot.ratings.map { Words.name($0) }.joined(separator: ", ") + ", \(Format.number(Int(pilot.hours))) hours")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text(status(pilot, registrations: registrations, now: now)).pixelFont(10.667).foregroundStyle(pilot.isAvailable(at: now) ? Theme.info : Theme.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 6) {
                        Button { training = pilot.id } label: { HangarButtonText("Train") }.buttonStyle(.small).disabled(pilot.trainingFor != nil)
                        // A spare pilot costs a salary for nothing: they can be let go. A pilot flying an aircraft stays.
                        if spare && pilot.trainingFor == nil {
                            Button { session.perform { try $0.dismissPilot(id: pilot.id) } } label: { HangarButtonText("Let go") }
                                .buttonStyle(.smallDanger)
                                .accessibilityHint("Takes \(pilot.name) off the payroll.")
                        }
                    }
                }
                .padding(12).background(PixelPanel())
            }
            SectionTitle("Looking for work")
            if world.ops.pilotMarket.isEmpty {
                EmptyNote("Nobody is looking for work right now. New pilots come every week.")
            }
            ForEach(world.ops.pilotMarket) { pilot in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pilot.name.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(pilot.ratings.map { Words.name($0) }.joined(separator: ", ")), \(Format.number(Int(pilot.hours))) hours")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text("Salary \(Format.dollars(pilot.salaryPerMonth)) a month").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { session.perform(sound: .coin) { try $0.hirePilot(id: pilot.id) } } label: { HangarButtonText("Hire for \(Format.compactMoney(pilot.hireFee))") }
                        .buttonStyle(.smallProminent)
                }
                .padding(12).background(PixelPanel())
            }
            Text("An aircraft needs pilots rated on its type. Spare pilots step in when someone is sick or on a course. New faces come every week.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Every aircraft's registration by id (if an id were ever repeated, the first wins, as with `first(where:)`).
    static func registrationsByID(_ world: World) -> [Int: String] {
        Dictionary(world.aircraft.map { ($0.id, $0.registration) }, uniquingKeysWith: { first, _ in first })
    }

    private func status(_ pilot: Pilot, registrations: [Int: String], now: Int) -> String {
        if let group = pilot.trainingFor, pilot.trainingUntilMinute > now {
            return "On a \(Words.name(group).lowercased()) course until \(Format.date(GameClock(minute: pilot.trainingUntilMinute).date))"
        }
        if pilot.sickUntilMinute > now { return "Off sick until \(Format.date(GameClock(minute: pilot.sickUntilMinute).date))" }
        if let id = pilot.aircraftID, let registration = registrations[id] { return "Flies \(registration)" }
        return "Spare"
    }
}

/// Sending a pilot on a type course. When the pilot is the only one who can fly their aircraft, the sheet says the aircraft
/// stays on the ground for the whole course and asks before sending them.
struct TrainingSheet: View {
    let session: GameSession
    let pilotID: Int
    @Environment(\.dismiss) private var dismiss
    /// The course waiting for the player's yes, when sending the pilot grounds their aircraft.
    @State private var confirming: RatingGroup?

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Type course") { Button { dismiss() } label: { HangarButtonText("Close") }.buttonStyle(.small) }
            HangarNotice(session: session)
            if let pilot = world.ops.pilots.first(where: { $0.id == pilotID }) {
                let groups = RatingGroup.allCases.filter { !pilot.isRated($0) }
                let grounds = TrainingSheet.groundedAircraft(pilot, in: world)
                Text("\(pilot.name) is away for the course and then rated on the new type.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let grounds {
                    Text("\(grounds) has no other pilot: it stays on the ground until the course ends. Hire a spare rated on it first if it should keep flying.")
                        .pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                }
                if groups.isEmpty { EmptyNote("\(pilot.name) is already rated on every type.") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groups, id: \.self) { group in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Words.name(group).uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(World.trainingDays(group)) days away, \(Format.dollars(world.trainingPrice(group)))").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    if grounds != nil { confirming = group } else { send(group) }
                                } label: { HangarButtonText("Send") }.buttonStyle(.smallProminent)
                            }
                            .padding(12).background(PixelPanel())
                        }
                    }
                }
            } else {
                EmptyNote("This pilot has left the airline.")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
        .onAppear { session.notice = nil }
        .pixelConfirm("Ground the aircraft?", message: confirmMessage(world), confirm: "Send anyway", destructive: true,
                      isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            if let group = confirming { send(group) }
        }
    }

    private func send(_ group: RatingGroup) {
        if session.perform(sound: .coin, { try $0.train(pilotID: pilotID, for: group) }) { dismiss() }
    }

    /// "C-FTEH stays on the ground until 3 Feb 1991, the end of the course."
    private func confirmMessage(_ world: World) -> String? {
        guard let group = confirming, let pilot = world.ops.pilots.first(where: { $0.id == pilotID }),
              let plane = TrainingSheet.groundedAircraft(pilot, in: world) else { return nil }
        let until = world.clock.minute + World.trainingDays(group) * GameClock.minutesPerDay
        return "\(plane) stays on the ground until \(Format.date(GameClock(minute: until).date)), the end of the course. Its route earns nothing in that time."
    }

    /// The registration of the aircraft that cannot fly without this pilot (the core's own check, World.isNeededCrew), or nil.
    static func groundedAircraft(_ pilot: Pilot, in world: World) -> String? {
        guard world.isNeededCrew(pilotID: pilot.id), let id = pilot.aircraftID else { return nil }
        return world.aircraft.first { $0.id == id }?.registration
    }
}
