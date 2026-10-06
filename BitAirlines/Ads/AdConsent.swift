import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import AppTrackingTransparency
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

/// The questions before the first ad, asked at the first "Watch an ad" tap and never at launch: a short explanation in the
/// game's own style with one Continue button, then (with AdMob built in) Google's consent form where the law needs one (EU, UK,
/// Switzerland) and Apple's tracking question. The player answers those two in Google's and Apple's own screens; either answer
/// is fine: the same ads play, only less suited to them.
/// The explanation has no "Not now": Apple rejects a message before its tracking question that lets the player skip it. The ad
/// itself stays optional, because this screen only comes after the player tapped a Watch an ad button.
@MainActor
enum AdConsent {
    private static let explainedKey = "ads.explained"

    static var hasExplained: Bool { UserDefaults.standard.bool(forKey: explainedKey) }

    /// The first time: shows the explanation, asks the questions, then calls `done(true)`. Every later time it calls
    /// `done(true)` at once. `done(false)` only when there was no screen to show the explanation on.
    static func beforeAd(from host: UIViewController?, done: @escaping (Bool) -> Void) {
        guard !hasExplained else { done(true); return }
        var shown: UIViewController?
        let view = AdExplainView(asksTracking: asksTracking) {
            UserDefaults.standard.set(true, forKey: explainedKey)
            shown?.dismiss(animated: true) {
                askQuestions { done(true) }
            }
        }
        shown = Ads.present(view, over: host, dimmed: true)
        if shown == nil { done(false) }
    }

    /// True when the network may be asked for ads: consent was given where it is needed, or it is not needed.
    static var canRequestAds: Bool {
        #if canImport(UserMessagingPlatform)
        return ConsentInformation.shared.canRequestAds
        #else
        return true
        #endif
    }

    /// Fetches the player's consent status (no form is shown), then reports `canRequestAds`.
    static func refresh(done: @escaping (Bool) -> Void) {
        #if canImport(UserMessagingPlatform)
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { _ in
            Task { @MainActor in done(canRequestAds) }
        }
        #else
        done(true)
        #endif
    }

    /// True when Google says the player must be able to change or withdraw their ad consent (EU, UK, Switzerland). Known only
    /// after `refresh`. Always false without the consent package.
    static var privacyChoicesRequired: Bool {
        #if canImport(UserMessagingPlatform)
        return ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        #else
        return false
        #endif
    }

    /// Google's form to change or withdraw ad consent (the "Ad privacy choices" button in Settings). Afterwards the ads follow
    /// the new answer: an ad loaded under the old one is dropped and a new one is asked for only where it is allowed.
    static func showPrivacyChoices(done: @escaping () -> Void) {
        #if canImport(UserMessagingPlatform)
        ConsentForm.presentPrivacyOptionsForm(from: Ads.topController()) { _ in
            Task { @MainActor in
                #if canImport(GoogleMobileAds)
                (Ads.service as? AdMobService)?.consentChanged()
                #endif
                done()
            }
        }
        #else
        done()
        #endif
    }

    /// One line for the Privacy card in Settings, or nil when no ad network is built in.
    static var privacyNote: String? {
        #if canImport(GoogleMobileAds)
        return "Ads are shown by Google AdMob. They use your activity in other apps only if you allowed it. You can change that in the iPhone Settings app, Privacy and Security, Tracking."
        #else
        return nil
        #endif
    }

    private static var asksTracking: Bool {
        #if canImport(GoogleMobileAds)
        return true
        #else
        return false
        #endif
    }

    private static func askQuestions(then next: @escaping () -> Void) {
        #if canImport(GoogleMobileAds)
        askConsent { askTracking(then: next) }
        #else
        next()
        #endif
    }

    #if canImport(GoogleMobileAds)
    /// Google's consent form, only where the law needs it (the form decides).
    private static func askConsent(then next: @escaping () -> Void) {
        #if canImport(UserMessagingPlatform)
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { _ in
            Task { @MainActor in
                ConsentForm.loadAndPresentIfRequired(from: Ads.topController()) { _ in
                    Task { @MainActor in next() }
                }
            }
        }
        #else
        next()
        #endif
    }

    /// Apple's tracking question, once. The words are NSUserTrackingUsageDescription (tools/generate_xcodeproj.rb).
    private static func askTracking(then next: @escaping () -> Void) {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { next(); return }
        ATTrackingManager.requestTrackingAuthorization { _ in
            Task { @MainActor in next() }
        }
    }
    #endif
}

/// The plain explanation before the first ad. One button: Continue always leads on to Google's and Apple's questions.
struct AdExplainView: View {
    let asksTracking: Bool
    let finish: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PixelIconView(icon: .tv, pixel: 2).foregroundStyle(Theme.accent)
                    Text("ABOUT ADS").pixelFont(16).foregroundStyle(Theme.accent)
                }
                Text("Ads are always your choice. One plays only when you tap a Watch an ad button, and the reward comes when it ends. Closing it early costs nothing.")
                    .pixelFont(10.667).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                if asksTracking {
                    Text("Next you may be asked about ad privacy, and whether ads can use your activity in other apps. Either answer is fine: you see the same number of ads.")
                        .pixelFont(10.667).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                Button("Continue") { finish() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(16).frame(maxWidth: 460)
            .background(PixelPanel(fill: Theme.surface, border: Theme.accent.opacity(0.7)))
            .padding(24)
            .accessibilityAddTraits(.isModal)
        }
    }
}
