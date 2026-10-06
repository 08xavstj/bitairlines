import SwiftUI
import CoreWorld

/// The sponsor boost on the Money screen: what it pays, the days in hand, and the optional ad that adds a day.
/// Shown only while a boost is running or one can be watched for.
struct SponsorCard: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        let days = world.sponsorDaysLeft
        let offer = world.rewardOffer(.sponsorBoost, realDay: RealDay.today())
        if days > 0 || (offer != nil && (Ads.service.isReady || Ads.service.skipsAds)) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SPONSOR").pixelFont(13.333).foregroundStyle(Theme.accent)
                        Spacer()
                        if days > 0 { Tag(text: "\(days) day\(days == 1 ? "" : "s") left", color: Theme.good) }
                    }
                    Text(explain).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                    if world.lastSponsorPayment > 0 {
                        KeyValueRow("Last payment", Format.dollars(world.lastSponsorPayment), color: Theme.good)
                    }
                    RewardButton(session: session, kind: .sponsorBoost)
                }
            }
        }
    }

    private var explain: String {
        let share = Int((Tuning.sponsorRevenueShare * 100).rounded())
        return "A sponsor pays \(share)% of each day's route income at midnight, on top of your fares. Each ad adds a day, up to \(Tuning.sponsorMaxDays)."
    }
}
