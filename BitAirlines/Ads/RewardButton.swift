import SwiftUI
import CoreWorld

/// "Watch an ad: <reward>". Shown only when the world offers the reward (not capped, something to apply it to) and an ad is
/// ready; nothing at all otherwise. The game pauses while the ad plays. If the ad does not finish, nothing is lost and the
/// button says so. With `once`, it hides after one reward (for a summary that should only pay once).
struct RewardButton: View {
    let session: GameSession
    let kind: RewardKind
    /// The aircraft, issue, job or listing id, or the away profit for `.awayDouble`.
    var target: Int? = nil
    var once = false
    @State private var busy = false
    @State private var taken = false
    @State private var note: String?

    var body: some View {
        let service = Ads.service
        let offer = session.world.rewardOffer(kind, realDay: RealDay.today(), target: target)
        // A Group, so a hidden button leaves no gap in the card around it.
        Group {
            if let offer, !(once && taken), service.isReady || service.skipsAds {
                Button { watch() } label: {
                    HStack(spacing: 6) {
                        PixelIconView(icon: .tv, pixel: 1)
                        Text((service.skipsAds ? "Take it: " : "Watch an ad: ") + RewardWords.reward(offer))
                    }
                }
                .buttonStyle(.small)
                .disabled(busy)
                .accessibilityHint("Optional. Plays a short ad, then gives the reward.")
            }
            if let note, offer != nil, !taken {
                Text(note).pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func watch() {
        let day = RealDay.today()
        let speed = session.speed
        busy = true
        note = nil
        let finish: (Bool) -> Void = { earned in
            busy = false
            if speed != .paused { session.setSpeed(speed) }
            guard earned else {
                note = "The ad did not finish, so there is no reward. Nothing was lost."
                return
            }
            if session.perform(sound: .coin, { try $0.grantReward(kind, realDay: day, target: target) }) {
                taken = true
                session.save()
            }
        }
        if Ads.service.skipsAds {
            finish(true)
            return
        }
        session.setSpeed(.paused)
        AdConsent.beforeAd(from: Ads.topController()) { go in
            guard go else {
                busy = false
                if speed != .paused { session.setSpeed(speed) }
                return
            }
            Ads.service.showRewarded(from: Ads.topController(), completion: finish)
        }
    }
}

/// The words for each reward, from the numbers the world gives.
enum RewardWords {
    static func reward(_ offer: RewardOffer) -> String {
        switch offer.kind {
        case .awayDouble: return "the away profit again, \(Format.compactMoney(offer.cash))"
        case .sponsorBoost:
            let share = Int((Tuning.sponsorRevenueShare * 100).rounded())
            return "a sponsor pays \(share)% of a day's route income"
        case .instantCheck: return "finish the work now"
        case .doubleGoalBonus: return "double the bonus, +\(Format.compactMoney(offer.cash))"
        case .overdraftSponsor: return "a sponsor covers a week of costs, \(Format.compactMoney(offer.cash))"
        case .freeMechanic: return "the mechanic flies in free"
        case .doubleJobPay: return "double the pay, +\(Format.compactMoney(offer.cash))"
        case .freePosters: return "a free posters campaign"
        case .newJobs: return "new jobs now"
        case .holdRareFind: return "keep it for sale \(offer.days) more days"
        case .brokersTip: return "a broker's tip, \(offer.count) more aircraft"
        }
    }
}
