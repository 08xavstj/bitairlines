import SwiftUI
import CoreCatalog
import CoreWorld

/// The job board: one-off work near the network, the jobs being flown, and what is going on in the world.
struct JobsScreen: View {
    let session: GameSession
    @State private var picking: Int?
    /// Show only the jobs one of the player's aircraft can fly now.
    @State private var onlyFlyable = true

    var body: some View {
        let world = session.world
        let open = world.ops.jobs.filter { !$0.isTaken }
        let taken = world.ops.jobs.filter { $0.isTaken }
        let choices = PlaneChoiceCache.shared.jobChoices(world: world)
        let shown = onlyFlyable ? open.filter { job in choices[job.id]?.contains(where: \.canDo) ?? false } : open
        let planes = PlaneChoiceWords.planesByID(world)
        Page(lazy: true) {
            ScreenHeader(title: "Jobs") { Text("\(open.count) on offer").pixelFont(10.667).foregroundStyle(Theme.textMuted) }
            if !taken.isEmpty {
                SectionTitle("Being flown")
                ForEach(taken) { job in
                    JobCard(world: world, job: job) {
                        VStack(alignment: .trailing, spacing: 6) {
                            if !job.loaded {
                                Button("Drop job") { session.perform { try $0.dropJob(jobID: job.id) } }
                                    .buttonStyle(.smallDanger)
                                    .accessibilityHint("The aircraft goes back to its route. Costs a little reputation.")
                            }
                            JobMapButton(session: session, job: job)
                        }
                    }
                }
            }
            SectionTitle("On offer")
            Toggle(isOn: $onlyFlyable) {
                Text("Jobs I can fly").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }.toggleStyle(PixelToggleStyle())
            if open.isEmpty {
                EmptyNote("No jobs right now. New ones turn up every day near the airports you fly to.")
            } else if shown.count < open.count {
                EmptyNote(shown.isEmpty ? "None of your aircraft can fly the jobs on offer right now. Turn off Jobs I can fly to see them and why."
                                        : "\(open.count - shown.count) more on offer that none of your aircraft can fly now. Turn off Jobs I can fly to see them.")
            }
            RewardButton(session: session, kind: .newJobs)
            ForEach(shown) { job in
                let flyers = PlaneChoiceWords.jobFlyers(choices[job.id] ?? [], job: job, planes: planes)
                JobCard(world: world, job: job) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if flyers.good {
                            Button("Fly it") { picking = job.id }
                                .buttonStyle(.smallProminent)
                                .accessibilityHint("Choose the aircraft that flies this job.")
                        } else {
                            Button("Why not") { picking = job.id }
                                .buttonStyle(.small)
                                .accessibilityHint("Shows each aircraft and why it cannot fly this job.")
                        }
                        JobMapButton(session: session, job: job)
                    }
                } footer: {
                    Text(flyers.text).pixelFont(10.667).foregroundStyle(flyers.good ? Theme.good : Theme.bad)
                        .fixedSize(horizontal: false, vertical: true)
                    RewardButton(session: session, kind: .doubleJobPay, target: job.id)
                }
            }
            Text("A job takes an aircraft off its route until it is done; then it goes back by itself. Late jobs pay half.")
                .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            // The news sits under the jobs, so the jobs are the first thing on the screen.
            if !world.ops.events.isEmpty || !world.ops.offers.isEmpty { EventsCard(session: session) }
        }
        .sheet(item: Binding(get: { picking.map { SheetID(id: $0) } }, set: { picking = $0?.id })) { sheet in
            JobAssignSheet(session: session, jobID: sheet.id)
        }
        // A stopping issue is drawn under any sheet: close the sheet so the player sees it.
        .onChange(of: session.world.isPausedByIssue) { _, now in if now { picking = nil } }
    }
}

/// Opens the map framed on a job's pickup and drop-off.
struct JobMapButton: View {
    let session: GameSession
    let job: Job

    var body: some View {
        Button("Map") { session.mapFocus = [job.from, job.to] }
            .buttonStyle(.small)
            .accessibilityLabel("Show \(Place.name(job.from)) and \(Place.name(job.to)) on the map")
    }
}

/// One job: what, where, how much, by when.
/// The route is the bold first line and always wraps in full; the kind tags sit on their own row under it, so they never
/// push the city names off. `trailing` is a narrow column of actions on the right; `footer` is a full-width row under the details.
struct JobCard<Trailing: View, Footer: View>: View {
    let world: World
    let job: Job
    let trailing: Trailing
    let footer: Footer

    init(world: World, job: Job, @ViewBuilder trailing: () -> Trailing, @ViewBuilder footer: () -> Footer) {
        self.world = world
        self.job = job
        self.trailing = trailing()
        self.footer = footer()
    }

    var body: some View {
        let km = AirportCatalog.airport(job.from).flatMap { a in AirportCatalog.airport(job.to).map { a.distanceKm(to: $0) } } ?? 0
        Card {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Place.name(job.from)) to \(Place.name(job.to))")
                        .pixelFont(13.333).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Tag(text: Words.name(job.kind), color: job.kind == .medevac || job.kind == .evacuation ? Theme.bad : Theme.info)
                        if let tag = CalendarWords.jobTag(job) { Tag(text: tag, color: Theme.gold) }
                    }
                    Text(load + ", \(Format.km(km)). Pays \(Format.dollars(job.pay)).")
                        .pixelFont(10.667).foregroundStyle(Theme.good).fixedSize(horizontal: false, vertical: true)
                    Text(timing).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    if let id = job.aircraftID, let plane = world.aircraft.first(where: { $0.id == id }) {
                        Text("\(plane.registration): \(job.loaded ? "on the way" : "going to the pickup")")
                            .pixelFont(10.667).foregroundStyle(Theme.info).fixedSize(horizontal: false, vertical: true)
                    }
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

extension JobCard where Footer == EmptyView {
    /// A job card with no footer row.
    init(world: World, job: Job, @ViewBuilder trailing: () -> Trailing) {
        self.init(world: world, job: job, trailing: trailing, footer: { EmptyView() })
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sponsor the \(Words.name(offer.kind).lowercased()) at \(Place.name(offer.airport)) for \(Format.compactMoney(offer.costUSD)): people remember who helped.")
                            .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Sponsor it") { session.perform(sound: .coin) { try $0.acceptOffer(id: offer.id) } }.buttonStyle(.smallProminent)
                            Button("No thanks") { session.perform { try $0.declineOffer(id: offer.id) } }.buttonStyle(.small)
                        }
                    }
                }
            }
        }
    }
}
