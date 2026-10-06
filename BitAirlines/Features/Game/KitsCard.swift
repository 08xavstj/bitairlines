import SwiftUI
import CoreCatalog
import CoreWorld

/// Kits for one aircraft (floats, skis, gravel and STOL kits, freighter), and its crew.
struct KitsCard: View {
    let session: GameSession
    let aircraftID: Int

    var body: some View {
        let world = session.world
        if let plane = world.aircraft.first(where: { $0.id == aircraftID }), let type = plane.type {
            let crew = world.ops.pilots.filter { $0.aircraftID == plane.id }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    KeyValueRow("Crew", crew.isEmpty ? "No pilots yet" : crew.map(\.name).joined(separator: ", "), color: crew.isEmpty ? Theme.bad : Theme.textPrimary)
                    if let jobID = plane.jobID, let job = world.ops.jobs.first(where: { $0.id == jobID }) {
                        KeyValueRow("On a job", "\(Words.name(job.kind)) to \(Place.name(job.to))", color: Theme.info)
                    }
                    ForEach(Kit.allCases.filter { $0.fits(type) || plane.kits.contains($0) }, id: \.self) { kit in
                        let fitted = plane.kits.contains(kit)
                        let problem = world.kitProblem(kit, aircraftID: plane.id)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Words.name(kit).uppercased()).pixelFont(10.667).foregroundStyle(fitted ? Theme.good : Theme.textPrimary)
                                Text(Words.explain(kit) + (fitted ? "" : " \(Format.dollars(world.kitPrice(kit, type: type))), \(kit.days) days in the hangar."))
                                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if fitted {
                                Button("Take off") { session.perform { try $0.remove(kit, aircraftID: plane.id) } }.buttonStyle(.small)
                            } else {
                                Button("Fit") { session.perform(sound: .coin) { try $0.fit(kit, aircraftID: plane.id) } }.buttonStyle(.smallProminent)
                                    .disabled(problem != nil)
                            }
                        }
                    }
                }
            }
        }
    }
}
