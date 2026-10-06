import SwiftUI
import CoreCatalog
import CoreWorld

/// Choosing which aircraft flies a job. The aircraft that can take it come first, each with what it will do; the others are
/// greyed underneath with the reason and cannot be picked, so a tap never ends in a refusal known beforehand.
struct JobAssignSheet: View {
    let session: GameSession
    let jobID: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Who flies it?") { Button("Close") { dismiss() }.buttonStyle(.small) }
            if let job = world.ops.jobs.first(where: { $0.id == jobID }) {
                let choices = PlaneChoiceCache.shared.choices(world: world, jobID: jobID)
                let planes = PlaneChoiceWords.planesByID(world)
                JobCard(world: world, job: job) { EmptyView() }
                if world.aircraft.isEmpty {
                    EmptyNote("You have no aircraft yet. Buy one in the Hangar, then come back to fly this job.")
                } else if !choices.contains(where: \.canDo) {
                    EmptyNote("None of your aircraft can fly this job now. Each one says why.")
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(choices) { choice in
                            if let plane = planes[choice.aircraftID] {
                                JobPlaneRow(world: world, job: job, plane: plane, choice: choice) {
                                    if session.perform({ try $0.takeJob(jobID: jobID, aircraftID: plane.id) }) { dismiss() }
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyNote("That job has gone.")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
    }
}

/// One aircraft in the job sheet: what it will do, or (greyed) why it cannot.
struct JobPlaneRow: View {
    let world: World
    let job: Job
    let plane: Aircraft
    let choice: PlaneChoice
    let onFly: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(plane.registration)  \(plane.type?.name ?? "")")
                    .pixelFont(13.333).foregroundStyle(choice.canDo ? Theme.textPrimary : Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                if let problem = choice.problem {
                    Text("Cannot fly it: " + PlaneChoiceWords.jobReason(problem, job: job, plane: plane))
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(PlaneChoiceWords.jobPlan(choice, job: job, jobHours: world.jobFlightHours(jobID: job.id, aircraftID: plane.id)))
                        .pixelFont(10.667).foregroundStyle(Theme.good).fixedSize(horizontal: false, vertical: true)
                    Text(plane.routeID == nil ? "Now at \(Place.name(world.nextGround(of: plane)))." : "Leaves \(FleetText.routeName(plane, in: world)) until the job is done.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if choice.canDo {
                Button("Fly this job") { onFly() }.buttonStyle(.smallProminent)
            }
        }
        .padding(12)
        .background(PixelPanel())
        .opacity(choice.canDo ? 1 : 0.6)
    }
}
