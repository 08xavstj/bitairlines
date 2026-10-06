import SwiftUI
import CoreCatalog
import CoreWorld

/// The logbook, opened from the menu: airports landed at (by region and country), aircraft types flown, rare finds bought,
/// dispatch stamps, and the paint schemes earned (with a way to paint them on an aircraft).
struct LogbookScreen: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        let book = world.logbook
        VStack(spacing: 0) {
            ScreenHeader(title: "Logbook") { Button("Close") { dismiss() }.buttonStyle(.small) }
                .padding(.horizontal, 16).padding(.top, 16)
            Page {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        KeyValueRow("Airports landed at", Format.number(book.airports.count))
                        KeyValueRow("Countries", Format.number(book.countriesVisited.count))
                        KeyValueRow("Aircraft types flown", Format.number(book.types.count))
                        KeyValueRow("Rare finds bought", Format.number(book.rareFinds.count))
                        KeyValueRow("Dispatch stamps", Format.number(world.ops.dispatch.stamps))
                    }
                }
                LogbookLiveries(session: session)
                SectionTitle("Regions")
                if book.airports.isEmpty { EmptyNote("Every airport your aircraft land at gets a stamp here.") }
                ForEach(book.regionsVisited, id: \.region) { row in KeyValueRow(row.region.displayName, Self.airports(row.airports)) }
                SectionTitle("Countries")
                ForEach(book.countriesVisited, id: \.country) { row in
                    KeyValueRow(CountryCatalog.country(row.country)?.name ?? row.country, Self.airports(row.airports))
                }
                SectionTitle("Aircraft types")
                if book.types.isEmpty { EmptyNote("Each type you fly is logged with the date of its first flight.") }
                ForEach(book.typesInOrder, id: \.typeID) { row in
                    KeyValueRow(AircraftCatalog.type(row.typeID)?.displayName ?? row.typeID, "First flown \(Format.date(CalendarDate(dayIndex: row.firstDay)))")
                }
                SectionTitle("Rare finds")
                if book.rareFinds.isEmpty { EmptyNote("Rare finds you buy in the hangar are kept here.") }
                ForEach(Array(book.rareFinds.enumerated()), id: \.offset) { _, find in
                    KeyValueRow("\(AircraftCatalog.type(find.typeID)?.displayName ?? find.typeID), \(Words.name(find.kind).lowercased())",
                                Format.date(CalendarDate(dayIndex: find.day)))
                }
                SectionTitle("Airports")
                ForEach(book.airportCodes, id: \.self) { code in
                    let landings = book.airports[code]?.landings ?? 0
                    KeyValueRow(Place.name(code), landings == 1 ? "1 landing" : "\(Format.number(landings)) landings")
                }
            }
        }
        .screenBackground()
    }

    static func airports(_ n: Int) -> String { n == 1 ? "1 airport" : "\(Format.number(n)) airports" }
}

/// The paint schemes earned from dispatch stamps and seasonal events, each with a list of aircraft to paint.
struct LogbookLiveries: View {
    let session: GameSession
    @State private var picking: String?

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Paint schemes earned")
            if world.unlockedLiveries.isEmpty {
                EmptyNote("Earn one with \(Tuning.stampsPerReward) dispatch stamps, or by flying \(Tuning.seasonJobsForLivery) jobs during a seasonal event.")
            }
            ForEach(world.unlockedLiveries, id: \.self) { code in
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Words.liveryName(code)).pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Button(picking == code ? "Done" : "Paint") { picking = picking == code ? nil : code }.buttonStyle(.small)
                        }
                        if picking == code { planes(code, world: world) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func planes(_ code: String, world: World) -> some View {
        ForEach(world.aircraft) { plane in
            HStack {
                Text("\(plane.registration)  \(plane.type?.name ?? "")").pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                Spacer()
                if plane.livery?.name == code {
                    Text("Wearing it").pixelFont(10.667).foregroundStyle(Theme.good)
                } else {
                    Button("Paint") { session.perform(sound: .coin) { try $0.paintEarnedLivery(code: code, aircraftID: plane.id) } }
                        .buttonStyle(.smallProminent)
                }
            }
        }
    }
}
