import SwiftUI
import CoreCatalog
import CoreWorld

/// The job board: one-off work near the network, the jobs being flown, and what is going on in the world.
struct JobsScreen: View {
    let session: GameSession
    @State private var picking: Int?

    var body: some View {
        let world = session.world
        let open = world.ops.jobs.filter { !$0.isTaken }
        let taken = world.ops.jobs.filter { $0.isTaken }
        Page {
            ScreenHeader(title: "Jobs") { Text("\(open.count) on offer").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
            if !world.ops.events.isEmpty || !world.ops.offers.isEmpty { EventsCard(session: session) }
            if !taken.isEmpty {
                SectionTitle("Being flown")
                ForEach(taken) { job in
                    JobCard(world: world, job: job) {
                        if !job.loaded { Button("Give back") { session.perform { try $0.dropJob(jobID: job.id) } }.buttonStyle(.smallDanger) }
                    }
                }
            }
            SectionTitle("On offer")
            if open.isEmpty { EmptyNote("No jobs right now. New ones turn up every day around your network.") }
            ForEach(open) { job in
                JobCard(world: world, job: job) { Button("Fly it") { picking = job.id }.buttonStyle(.smallProminent) }
            }
            Text("A job takes an aircraft off its route until it is done; then it goes back by itself. Late jobs pay half.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: Binding(get: { picking.map { SheetID(id: $0) } }, set: { picking = $0?.id })) { sheet in
            JobAssignSheet(session: session, jobID: sheet.id)
        }
    }
}

/// One job: what, where, how much, by when.
struct JobCard<Trailing: View>: View {
    let world: World
    let job: Job
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let km = AirportCatalog.airport(job.from).flatMap { a in AirportCatalog.airport(job.to).map { a.distanceKm(to: $0) } } ?? 0
        Card {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Tag(text: Words.name(job.kind), color: job.kind == .medevac || job.kind == .evacuation ? Theme.bad : Theme.info)
                        Text("\(Place.name(job.from)) to \(Place.name(job.to))").pixelFont(13.333).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    }
                    Text(load + ", \(Format.km(km)). Pays \(Format.dollars(job.pay)).").pixelFont(10.667).foregroundStyle(Theme.good)
                    Text(timing).pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    if let id = job.aircraftID, let plane = world.aircraft.first(where: { $0.id == id }) {
                        Text("\(plane.registration): \(job.loaded ? "on the way" : "going to the pickup")").pixelFont(10.667).foregroundStyle(Theme.info)
                    }
                }
                Spacer(minLength: 4)
                trailing
            }
        }
    }

    private var load: String {
        var parts: [String] = []
        if job.passengers > 0 { parts.append("\(job.passengers) \(job.passengers == 1 ? "person" : "people")") }
        if job.cargoKg > 0 { parts.append("\(Format.number(job.cargoKg)) kg") }
        return parts.joined(separator: " and ")
    }

    private var timing: String {
        let deadline = GameClock(minute: job.deadlineMinute)
        var line = "Land by \(Format.date(deadline.date)) \(Format.time(deadline))."
        if !job.isTaken { line += " Offer ends in \(Format.duration(minutes: max(0, job.expiresMinute - world.clock.minute)))." }
        return line
    }
}

/// Choosing which aircraft flies a job.
struct JobAssignSheet: View {
    let session: GameSession
    let jobID: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Who flies it?") { Button("Close") { dismiss() }.buttonStyle(.small) }
            if let job = world.ops.jobs.first(where: { $0.id == jobID }) {
                JobCard(world: world, job: job) { EmptyView() }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(world.aircraft) { plane in
                            let problem = world.jobProblem(jobID: jobID, aircraftID: plane.id)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(plane.registration)  \(plane.type?.name ?? "")").pixelFont(13.333).foregroundStyle(Theme.textPrimary)
                                    if let problem {
                                        Text(Messages.describe(problem)).pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text(plane.routeID == nil ? "Parked at \(Place.name(plane.location))" : "Leaves \(FleetText.routeName(plane, in: world)) until the job is done")
                                            .pixelFont(10.667).foregroundStyle(Theme.textMuted)
                                    }
                                }
                                Spacer()
                                Button("Take the job") {
                                    if session.perform({ try $0.takeJob(jobID: jobID, aircraftID: plane.id) }) { dismiss() }
                                }
                                .buttonStyle(.smallProminent).disabled(problem != nil)
                            }
                            .padding(10).background(PixelPanel())
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

/// What is happening in the world, and offers to say yes or no to.
struct EventsCard: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("IN THE NEWS").pixelFont(13.333).foregroundStyle(Theme.gold)
                ForEach(world.ops.events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Words.name(event.kind).uppercased()).pixelFont(10.667).foregroundStyle(Theme.textPrimary)
                        Text(Words.explain(event.kind, place: event.airport) + " Until \(Format.date(GameClock(minute: event.untilMinute).date)).")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(world.ops.offers) { offer in
                    HStack {
                        Text("Sponsor the \(Words.name(offer.kind).lowercased()) at \(Place.name(offer.airport)) for \(Format.compactMoney(offer.costUSD)): people remember who helped.")
                            .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Yes") { session.perform(sound: .coin) { try $0.acceptOffer(id: offer.id) } }.buttonStyle(.smallProminent)
                        Button("No") { session.perform { try $0.declineOffer(id: offer.id) } }.buttonStyle(.small)
                    }
                }
            }
        }
    }
}
