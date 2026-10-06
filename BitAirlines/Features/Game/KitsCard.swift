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
                    KeyValueRow("Crew", crew.isEmpty ? "None yet. Hire one under Fleet, Pilots." : crew.map(\.name).joined(separator: ", "), color: crew.isEmpty ? Theme.bad : Theme.textPrimary)
                    if let jobID = plane.jobID, let job = world.ops.jobs.first(where: { $0.id == jobID }) {
                        KeyValueRow("On a job", "\(Words.name(job.kind)) to \(Place.name(job.to))", color: Theme.info)
                    }
                    // A kit is fitted on the ground, so one line says so instead of the same refusal on every kit.
                    if !kitsOnGround(plane) {
                        Text("Kits are fitted while it is on the ground and not on a job.").pixelFont(10.667).foregroundStyle(Theme.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Kit.allCases.filter { $0.fits(type) || plane.kits.contains($0) }, id: \.self) { kit in
                        let fitted = plane.kits.contains(kit)
                        let problem = world.kitProblem(kit, aircraftID: plane.id)
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Words.name(kit).uppercased()).pixelFont(10.667).foregroundStyle(fitted ? Theme.good : Theme.textPrimary)
                                Text(Words.explain(kit) + (fitted ? "" : " \(Format.dollars(world.kitPrice(kit, type: type))), \(kit.days) days in the hangar."))
                                    .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                                if !fitted, let problem, problem != .aircraftBusy {
                                    Text(Messages.describe(problem)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if fitted {
                                Button { session.perform { try $0.remove(kit, aircraftID: plane.id) } } label: { HangarButtonText("Remove") }.buttonStyle(.small)
                            } else {
                                Button { session.perform(sound: .coin) { try $0.fit(kit, aircraftID: plane.id) } } label: { HangarButtonText("Fit") }.buttonStyle(.smallProminent)
                                    .disabled(problem != nil)
                            }
                        }
                    }
                }
            }
        }
    }

    /// True when the aircraft is where a kit can be fitted: idle or boarding, and not on a job.
    private func kitsOnGround(_ plane: Aircraft) -> Bool {
        if plane.jobID != nil { return false }
        switch plane.status {
        case .idle, .boarding: return true
        default: return false
        }
    }
}
