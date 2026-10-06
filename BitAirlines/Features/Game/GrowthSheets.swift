import SwiftUI
import CoreCatalog
import CoreWorld

/// Growing out of the bush: leaving an airport for good, and moving the headquarters to a bigger one.
/// Trading in an aircraft is in TradeInSheet.swift.

/// A red button that opens the leave sheet for one airport. Shown on the Bases screen and in the map's airport panel.
struct LeaveAirportButton: View {
    let session: GameSession
    let code: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { HangarButtonText("Leave this airport") }
            .buttonStyle(.smallDanger)
            .sheet(isPresented: $showing) { LeaveAirportSheet(session: session, code: code) }
    }
}

/// What leaving an airport does, and the button that does it.
struct LeaveAirportSheet: View {
    let session: GameSession
    let code: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        let plan = world.leaveAirportPlan(code: code)
        let problem = world.leaveAirportProblem(code: code)
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Leave \(Place.name(code))") { Button { dismiss() } label: { HangarButtonText("Cancel") }.buttonStyle(.small) }
            HangarNotice(session: session)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("You stop flying to \(Place.name(code)) for good.").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(Array(GrowthWords.leaveLines(plan).enumerated()), id: \.offset) { _, line in
                                Text(line).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                            }
                            KeyValueRow("You receive", Format.dollars(plan.total), color: Theme.good)
                        }
                    }
                    if let problem {
                        Text(Messages.describe(problem, cash: session.world.airline.cash)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        if session.perform(sound: .coin, { _ = try $0.leaveAirport(code: code) }) { dismiss() }
                    } label: { HangarButtonText("Leave \(Place.name(code))") }
                        .buttonStyle(.smallDanger)
                        .disabled(problem != nil)
                }
            }
        }
        .padding(16)
        .screenBackground()
        .onAppear { session.notice = nil }
    }
}

/// On the Airline screen: the button that opens the headquarters move (from the level that allows it).
struct MoveHeadquartersButton: View {
    let session: GameSession
    @State private var showing = false

    var body: some View {
        let level = session.world.airline.level
        let allowed = level >= Tuning.headquartersMoveLevel
        VStack(alignment: .leading, spacing: 4) {
            Button { showing = true } label: { HangarButtonText("Move headquarters") }
                .buttonStyle(.small)
                .disabled(!allowed)
            if !allowed {
                Text("From certificate level \(Tuning.headquartersMoveLevel) you can move your headquarters to a bigger airport.")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showing) { MoveHeadquartersSheet(session: session) }
    }
}

/// The biggest airports of the network the headquarters could move to, with the fee.
struct MoveHeadquartersSheet: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        let options = world.headquartersOptions()
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Move headquarters") { Button { dismiss() } label: { HangarButtonText("Close") }.buttonStyle(.small) }
            HangarNotice(session: session)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Now at \(Place.name(world.airline.home))\(MoveHeadquartersSheet.runwayNote(world, code: world.airline.home)). Routes, bases and aircraft stay as they are; aircraft parked at the old home can be put on any route.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    Text("New aircraft are delivered to the headquarters, or to the nearest airport you fly to that can take them. A long runway at home means the biggest aircraft arrive there.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    if options.isEmpty {
                        EmptyNote("None of the airports you fly to can be your headquarters yet. Open a route to a bigger town first.")
                    }
                    ForEach(options) { option in HeadquartersRow(session: session, option: option, onMoved: { dismiss() }) }
                }
            }
        }
        .padding(16)
        .screenBackground()
        .onAppear { session.notice = nil }
    }

    /// " (runway 6,000 ft)" for an airport with a runway, " (water)" for a water aerodrome.
    static func runwayNote(_ world: World, code: String) -> String {
        guard let airport = AirportCatalog.airport(code) else { return "" }
        if world.surface(at: airport) == .water { return " (water)" }
        return " (runway \(Format.number(world.runwayFt(at: airport))) ft)"
    }
}

/// One airport the headquarters could move to.
struct HeadquartersRow: View {
    let session: GameSession
    let option: HeadquartersOption
    let onMoved: () -> Void

    var body: some View {
        let world = session.world
        let problem = world.headquartersProblem(to: option.code)
        let people = AirportCatalog.airport(option.code)?.population ?? 0
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Place.name(option.code).uppercased()).pixelFont(13.333).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("About \(Format.people(people)) people nearby. The move costs \(Format.dollars(option.fee)).")
                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                let runway = HeadquartersRow.runwayLine(world, code: option.code)
                Text(runway.text).pixelFont(10.667).foregroundStyle(runway.fitsAll ? Theme.good : Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if let problem {
                    Text(Messages.describe(problem, cash: session.world.airline.cash)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if session.perform(sound: .coin, { try $0.moveHeadquarters(to: option.code) }) { onMoved() }
            } label: { HangarButtonText("Move here") }
                .buttonStyle(.smallProminent)
                .disabled(problem != nil)
        }
        .padding(12).background(PixelPanel())
    }

    /// The runway, and whether every aircraft of the airline's level (floatplanes aside) can be delivered there.
    static func runwayLine(_ world: World, code: String) -> (text: String, fitsAll: Bool) {
        guard let airport = AirportCatalog.airport(code) else { return (text: "", fitsAll: false) }
        if world.surface(at: airport) == .water { return (text: "A water aerodrome: only floatplanes can be delivered here.", fitsAll: false) }
        let have = world.runwayFt(at: airport)
        let need = DeliveryWords.longestRunwayNeeded(level: world.airline.level)
        let paved = world.surface(at: airport) == .paved
        if !world.ops.mode.checksRunways || (paved && have >= need) {
            return (text: "Runway \(Format.number(have)) ft: every aircraft of your level can be delivered here.", fitsAll: true)
        }
        return (text: "Runway \(Format.number(have)) ft\(paved ? "" : " gravel"): the biggest aircraft of your level need \(Format.number(need)) ft paved.", fitsAll: false)
    }
}
