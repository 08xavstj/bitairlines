import SwiftUI
import CoreCatalog
import CoreWorld

/// The pilots: who flies what, who is off sick or on a course, the pilots looking for work, and automatic hiring.
struct PilotsView: View {
    let session: GameSession
    @State private var training: Int?

    var body: some View {
        let world = session.world
        let now = world.clock.minute
        VStack(alignment: .leading, spacing: 10) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    KeyValueRow("Pilots", "\(world.ops.pilots.count)")
                    KeyValueRow("Salaries", "\(Format.dollars(world.pilotPayroll)) a month")
                    Toggle(isOn: Binding(get: { session.world.ops.autoHirePilots }, set: { v in session.world.setAutoHire(v) })) {
                        Text("Hire pilots automatically for new aircraft").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }.toggleStyle(PixelToggleStyle())
                }
            }
            SectionTitle("Your pilots")
            if world.ops.pilots.isEmpty {
                EmptyNote("No pilots yet. Hire one below, or turn on automatic hiring above.")
            }
            ForEach(world.ops.pilots) { pilot in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pilot.name.uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(pilot.ratings.map { Words.name($0) }.joined(separator: ", ") + ", \(Format.number(Int(pilot.hours))) hours")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Text(status(pilot, world: world, now: now)).pixelFont(10.667).foregroundStyle(pilot.isAvailable(at: now) ? Theme.info : Theme.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { training = pilot.id } label: { HangarButtonText("Train") }.buttonStyle(.small).disabled(pilot.trainingFor != nil)
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
            Text("An aircraft needs pilots rated on its type. Spare pilots step in when someone is sick. New faces come every week.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: Binding(get: { training.map { SheetID(id: $0) } }, set: { training = $0?.id })) { sheet in
            TrainingSheet(session: session, pilotID: sheet.id)
        }
        // A stopping issue is drawn under any sheet: close the sheet so the player sees it.
        .onChange(of: session.world.isPausedByIssue) { _, now in if now { training = nil } }
    }

    private func status(_ pilot: Pilot, world: World, now: Int) -> String {
        if let group = pilot.trainingFor, pilot.trainingUntilMinute > now {
            return "On a \(Words.name(group).lowercased()) course until \(Format.date(GameClock(minute: pilot.trainingUntilMinute).date))"
        }
        if pilot.sickUntilMinute > now { return "Off sick until \(Format.date(GameClock(minute: pilot.sickUntilMinute).date))" }
        if let id = pilot.aircraftID, let plane = world.aircraft.first(where: { $0.id == id }) { return "Flies \(plane.registration)" }
        return "Spare"
    }
}

/// Sending a pilot on a type course.
struct TrainingSheet: View {
    let session: GameSession
    let pilotID: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Type course") { Button { dismiss() } label: { HangarButtonText("Close") }.buttonStyle(.small) }
            HangarNotice(session: session)
            if let pilot = world.ops.pilots.first(where: { $0.id == pilotID }) {
                let groups = RatingGroup.allCases.filter { !pilot.isRated($0) }
                Text("\(pilot.name) is away for the course and then rated on the new type.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
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
                                    if session.perform(sound: .coin, { try $0.train(pilotID: pilotID, for: group) }) { dismiss() }
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
    }
}
