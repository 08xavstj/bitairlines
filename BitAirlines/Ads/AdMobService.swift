// Google AdMob rewarded ads. The whole file compiles to nothing unless the Google Mobile Ads package is in the project
// (BIT_ADS=1 ruby tools/generate_xcodeproj.rb, see docs/rewarded-ads.md). Written for Google Mobile Ads 12, where the Swift
// names dropped the GAD prefix (GADRewardedAd is RewardedAd, GADRequest is Request, GADMobileAds is MobileAds).
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import Observation
import UIKit

@MainActor
@Observable
final class AdMobService: NSObject, AdService, FullScreenContentDelegate {
    private(set) var isReady = false
    var skipsAds: Bool { false }

    @ObservationIgnored private var ad: RewardedAd?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var loading = false
    /// Set only by the network's reward callback; read when the ad closes.
    @ObservationIgnored private var earned = false
    @ObservationIgnored private var pending: ((Bool) -> Void)?
    /// A tap that came before consent was settled: show as soon as an ad loads (or give up after a few seconds).
    @ObservationIgnored private var waiting: (host: UIViewController?, completion: (Bool) -> Void)?
    /// Counts the waits, so the time limit of an earlier tap never ends a newer wait.
    @ObservationIgnored private var waitCount = 0

    /// The consent status is fetched first; ads load only where they may. Where consent is still needed (EU, UK,
    /// Switzerland), the button shows anyway: the first tap asks the question (AdConsent), then loads and plays an ad.
    func load() {
        guard !loading, ad == nil else { return }
        AdConsent.refresh { [weak self] canRequest in
            guard let self else { return }
            if canRequest {
                self.loadAd()
            } else {
                self.isReady = !AdConsent.hasExplained
            }
        }
    }

    private func loadAd() {
        guard !loading, ad == nil else { return }
        if !started {
            MobileAds.shared.start(completionHandler: nil)
            started = true
        }
        loading = true
        RewardedAd.load(with: AdConfig.rewardedUnitID, request: Request()) { [weak self] loaded, _ in
            Task { @MainActor in self?.didLoad(loaded) }
        }
    }

    private func didLoad(_ loaded: RewardedAd?) {
        loading = false
        ad = loaded
        ad?.fullScreenContentDelegate = self
        isReady = loaded != nil
        if let waiting {
            self.waiting = nil
            // The screen that asked may have been closed while the ad loaded: then show it over whatever is on top now.
            let host = waiting.host?.view.window != nil ? waiting.host : Ads.topController()
            if loaded != nil { showRewarded(from: host, completion: waiting.completion) } else { waiting.completion(false) }
            return
        }
        if loaded == nil {
            // No fill or no network: try again in a minute. The buttons stay hidden meanwhile.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self?.load()
            }
        }
    }

    func showRewarded(from host: UIViewController?, completion: @escaping (Bool) -> Void) {
        guard let ad else {
            // Consent is still missing after the questions: no ad may be asked for, so the buttons hide until it changes
            // (Settings, Ad privacy choices).
            guard AdConsent.canRequestAds else {
                isReady = false
                completion(false)
                return
            }
            // Consent was just given: load now and play when ready, or give up after a few seconds.
            waitCount += 1
            let mine = waitCount
            waiting = (host, completion)
            loadAd()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard let self, self.waitCount == mine, let waiting = self.waiting else { return }
                self.waiting = nil
                waiting.completion(false)
            }
            return
        }
        guard let host = host ?? Ads.topController() else { completion(false); return }
        self.ad = nil
        isReady = false
        earned = false
        pending = completion
        // The reward is granted only from this callback (the player watched long enough), never on a tap or a close.
        ad.present(from: host) { [weak self] in
            self?.earned = true
        }
    }

    private func finish() {
        let done = pending
        let got = earned
        pending = nil
        earned = false
        done?(got)
        load()
    }

    /// After the player changed their ad privacy choices: drop an ad loaded under the old answer, then load again where allowed.
    /// Does nothing while an ad is on screen (it finishes first, and `finish` loads the next one).
    func consentChanged() {
        guard pending == nil else { return }
        ad = nil
        isReady = false
        load()
    }

    // MARK: FullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        Task { @MainActor in
            self.earned = false
            self.finish()
        }
    }
}
#endif
