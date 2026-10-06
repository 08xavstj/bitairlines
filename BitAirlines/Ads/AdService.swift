import SwiftUI
import UIKit

/// Shows rewarded ads. Ads in this game are always the player's choice: a "Watch an ad" button appears only when an ad is
/// ready, and the reward is given only when the ad network says the player earned it (see docs/rewarded-ads.md).
@MainActor
protocol AdService: AnyObject {
    /// True when an ad can be shown now (the buttons appear only then).
    var isReady: Bool { get }
    /// True when the player has bought the option to skip ads: each offer becomes a plain button with the same caps.
    /// Nothing is sold yet (the owner adds it after the App Store launch), so this is false for now.
    var skipsAds: Bool { get }
    /// Starts loading the next ad. Safe to call often.
    func load()
    /// Shows an ad over `from` (or the top screen). `completion(true)` only when the player earned the reward.
    func showRewarded(from: UIViewController?, completion: @escaping (Bool) -> Void)
}

/// Every id the ad network needs, in one place. The defaults are Google's public TEST ids: they always show a test ad and
/// never pay. tools/generate_xcodeproj.rb reads `appID` from this file for Info.plist, so keep it on one line.
/// Before an App Store build with AdMob (BIT_ADS=1), both ids must be the real ones: see docs/app-store.md, section 4.
enum AdConfig {
    // TODO: replace with the real AdMob app id (AdMob, Apps, App settings) before the App Store build.
    static let appID = "ca-app-pub-3940256099942544~1458002511"
    // TODO: replace with the real rewarded ad unit id (AdMob, Apps, Ad units) before the App Store build.
    static let rewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    /// How long the stand-in ad runs when the ad network is not built in.
    static let placeholderSeconds = 5
    /// Without the ad network built in, the stand-in ad lets the flow be tested, but only in Debug builds (Xcode Run on a phone
    /// or the simulator). A Release build (Archive, TestFlight, the App Store) without AdMob hides every ad button instead.
    #if DEBUG
    static let placeholderWithoutSDK = true
    #else
    static let placeholderWithoutSDK = false
    #endif
}

#if canImport(GoogleMobileAds) && !DEBUG
// A reminder in Xcode's warning list for every Archive with AdMob built in. Delete these lines once AdConfig holds the real ids.
#warning("AdMob release build: check that AdConfig.appID and AdConfig.rewardedUnitID are the real ids, not Google's test ids.")
#endif

/// The one ad service the app uses.
@MainActor
enum Ads {
    static let service: any AdService = {
        let made = makeService()
        made.load()
        return made
    }()

    private static func makeService() -> any AdService {
        #if canImport(GoogleMobileAds)
        return AdMobService()
        #else
        return DevAdService()
        #endif
    }

    /// The screen on top, to show an ad or a question over it.
    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    /// Shows a SwiftUI view over the whole screen (an ad stand-in or a question). Returns the controller, to dismiss later.
    @discardableResult
    static func present<Content: View>(_ content: Content, over host: UIViewController?, dimmed: Bool) -> UIViewController? {
        guard let host = host ?? topController() else { return nil }
        let controller = UIHostingController(rootView: content)
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        controller.view.backgroundColor = dimmed ? .clear : UIColor(Theme.background)
        host.present(controller, animated: true)
        return controller
    }
}
