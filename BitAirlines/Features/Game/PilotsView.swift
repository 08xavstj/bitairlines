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
                    }.toggleStyle(PixelToggleStyle())
                }
            }
            SectionTitle("Your pilots")
            ForEach(world.ops.pilots) { pilot in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pilot.name).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                        Text(pilot.ratings.map { Words.name($0) }.joined(separator: ", ") + ", \(Format.number(Int(pilot.hours))) hours")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                        Text(status(pilot, world: world, now: now)).pixelFont(10.667).foregroundStyle(pilot.isAvailable(at: now) ? Theme.info : Theme.gold)
                    }
                    Spacer()
                    Button("Train") { training = pilot.id }.buttonStyle(.small).disabled(pilot.trainingFor != nil)
                }
                .padding(10).background(PixelPanel())
            }
            SectionTitle("Looking for work")
            ForEach(world.ops.pilotMarket) { pilot in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pilot.name).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                        Text("\(pilot.ratings.map { Words.name($0) }.joined(separator: ", ")), \(Format.number(Int(pilot.hours))) hours, \(Format.dollars(pilot.salaryPerMonth)) a month")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Button("Hire for \(Format.compactMoney(pilot.hireFee))") { session.perform(sound: .coin) { try $0.hirePilot(id: pilot.id) } }.buttonStyle(.smallProminent)
                }
                .padding(10).background(PixelPanel())
            }
            Text("An aircraft needs pilots rated on its type. Spare pilots step in when someone is sick. New faces come every week.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: Binding(get: { training.map { SheetID(id: $0) } }, set: { training = $0?.id })) { sheet in
            TrainingSheet(session: session, pilotID: sheet.id)
        }
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
            ScreenHeader(title: "Type course") { Button("Close") { dismiss() }.buttonStyle(.small) }
            if let pilot = world.ops.pilots.first(where: { $0.id == pilotID }) {
                Text("\(pilot.name) is away for the course and then rated on the new type.").pixelFont(10.667).foregroundStyle(Theme.textMuted)
                ForEach(RatingGroup.allCases.filter { !pilot.isRated($0) }, id: \.self) { group in
                    HStack {
                        Text("\(Words.name(group)): \(World.trainingDays(group)) days, \(Format.dollars(world.trainingPrice(group)))").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button("Send") {
                            if session.perform(sound: .coin, { try $0.train(pilotID: pilotID, for: group) }) { dismiss() }
                        }.buttonStyle(.smallProminent)
                    }
                    .padding(10).background(PixelPanel())
                }
            }
            if let notice = session.notice { Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold) }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
    }
}
