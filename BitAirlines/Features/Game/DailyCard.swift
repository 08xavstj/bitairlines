import SwiftUI
import CoreWorld

/// Today's dispatch: what it is, whether it has been flown, and the stamp card towards the next reward.
struct DailyDispatchCard: View {
    let world: World

    var body: some View {
        if world.realDay > 0 {
            let stamps = world.ops.dispatch.stamps
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("TODAY'S DISPATCH").pixelFont(13.333).foregroundStyle(Theme.accent)
                        Spacer()
                        Tag(text: CalendarWords.stamps(stamps), color: Theme.gold)
                    }
                    Text(status).pixelFont(10.667).foregroundStyle(world.dispatchStampedToday ? Theme.good : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .center, spacing: 10) {
                        StampRow(filled: Tuning.stampsPerReward - world.stampsToNextReward)
                        Text("\(CalendarWords.stamps(world.stampsToNextReward)) more for a classic paint scheme and a rare hangar find. Any days, not only in a row.")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var status: String {
        if world.dispatchStampedToday { return "Flown and stamped. A new dispatch comes tomorrow." }
        guard let job = world.dispatchToday else { return "No dispatch today: your network has nowhere to send one yet." }
        let line = "\(Words.name(job.kind)), \(Place.name(job.from)) to \(Place.name(job.to)). Pays \(Format.dollars(job.pay))."
        return line + (job.isTaken ? " Being flown." : " Find it on the Jobs board.")
    }
}

/// Seven squares, filled for the stamps on the current card.
struct StampRow: View {
    let filled: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<Tuning.stampsPerReward, id: \.self) { i in
                Rectangle().fill(i < filled ? Theme.gold : Theme.surfaceRaised).frame(width: 12, height: 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(Tuning.stampsPerReward) stamps")
    }
}

/// The seasonal event running now (with days left and progress to its paint scheme), or the next one.
struct SeasonCard: View {
    let world: World

    var body: some View {
        let today = world.realDay
        if today > 0 {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    if let season = world.activeSeason {
                        HStack {
                            Text("EVENT: \(CalendarWords.name(season.kind).uppercased())").pixelFont(13.333).foregroundStyle(Theme.gold)
                            Spacer()
                            Tag(text: "\(CalendarWords.days(season.daysLeft(from: today))) left", color: Theme.gold)
                        }
                        Text(CalendarWords.explain(season.kind)).pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text(progress(season.kind)).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        let next = SeasonalEvents.next(afterRealDay: today)
                        Text("NEXT EVENT: \(CalendarWords.name(next.kind).uppercased())").pixelFont(13.333).foregroundStyle(Theme.accent)
                        Text("Starts in \(CalendarWords.days(next.startDay - today)). \(CalendarWords.explain(next.kind))")
                            .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func progress(_ kind: SeasonKind) -> String {
        let need = Tuning.seasonJobsForLivery
        if world.unlockedLiveries.contains(UnlockableLiveries.seasonCode(kind)) { return "You have its paint scheme. Paint it from the Logbook in the menu." }
        return "Event jobs flown: \(min(world.ops.season.jobsDone, need)) of \(need) for its paint scheme. They are on the Jobs board."
    }
}
