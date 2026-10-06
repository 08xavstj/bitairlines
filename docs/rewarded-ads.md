# Rewarded ads

Built. The rule that shapes it: Apple, Google AdMob and AppLovin all require a rewarded ad to be the player's choice. The game
never forces one, never hides progress behind one, and never nags. A "Watch an ad" button appears only when the reward applies,
its cap is not used up and an ad is loaded. Players accept ads like this and punish forced ones (docs/review-2026-10.md).

## The placements (docs/growth-plan-2026-10.md, section 4)

A "profit day" is the airline's average daily operating result over the last 7 game days, at least $2,000, so cash rewards
matter at level 1 and level 7 alike. Caps count real days; the app passes the real day in (Core has no clock).

| # | Where (app file) | `RewardKind` | Reward | Cap |
|---|---|---|---|---|
| 1 | While-you-were-away summary (`AwaySummary.swift`) | `awayDouble` | The away profit paid again, up to 2 profit days | 3 a real day, once per summary |
| 2 | Money screen, Sponsor card (`Ads/SponsorCard.swift`) | `sponsorBoost` | A sponsor pays 25% of the day's route income at midnight, for 1 game day per ad, up to 4 days in hand | 4 a real day |
| 3 | Fleet, aircraft sheet, Upkeep card (`FleetScreen.swift`) | `instantCheck` | A check, repair or barn-find restoration finishes now | 3 a real day |
| 4 | Money screen, weekly goal card once met (`WeeklyGoalCard.swift`) | `doubleGoalBonus` | The goal bonus paid again | Once per goal, 1 a real day |
| 5 | Overdraft dialog (`GameShell.swift`, `IssueOptions`) | `overdraftSponsor` | A sponsor pays a week of fixed costs (head office and aircraft), at least $2,000. If that lifts the bank back within the overdraft limit, the overdraft notice goes | Once per overdraft |
| 6 | Breakdown dialog (`IssueOptions`) | `freeMechanic` | The fly-in mechanic option, free | Once per breakdown |
| 7 | Jobs board, next to "Fly it" (`JobsScreen.swift`) | `doubleJobPay` | One job's pay doubled | 1 a real day, once per job |
| 8 | Money screen, Marketing card (`MarketingCard.swift`) | `freePosters` | A posters campaign at no cost | Once per 14 game days, 1 a real day |
| 9 | Jobs board, above the offers (`JobsScreen.swift`) | `newJobs` | The open offers replaced (jobs being flown, the daily dispatch and seasonal jobs stay) | 1 a real day |
| 10 | Hangar, a rare find's card (`MarketScreen.swift`) | `holdRareFind` | The rare find stays for sale 7 more days | Once per listing |
| 11 | Hangar, Used tab (`MarketScreen.swift`) | `brokersTip` | Two extra used aircraft (types the airline may fly) until next Monday's turnover | Once per game week, 1 a real day |

Cash is booked as revenue, so it shows on the Money screen. The sponsor bonus is paid on top: fares and demand do not change.
Sandbox has no rewards (money never runs out there). A finished game has none either.

## How it is built

- **Core** (`AirlineCore/Sources/CoreWorld/Rewards.swift`, `RewardGrants.swift`): `RewardKind`,
  `world.rewardOffer(kind, realDay:, target:)` (nil when not on offer; carries the cash, days and count for the words) and
  `world.grantReward(kind, realDay:, target:)`. The caps and the sponsor days live in `Operations.rewards` (older saves load
  without it). The sponsor is paid in `dailyRewards()`, called from `OperationsDaily`. All numbers are in the `Tuning`
  extension in `Rewards.swift`. Tests: `RewardsTests.swift`.
- **App** (`BitAirlines/Ads/`):
  - `AdService.swift`: the `AdService` protocol, `AdConfig` (every id in one place) and `Ads.service`, the one service in use.
  - `DevAdService.swift`: the stand-in used while AdMob is not built in. A full-screen pixel "Ad placeholder" counts down 5
    seconds; closing early gives nothing. `AdConfig.placeholderWithoutSDK = false` hides every ad button instead.
  - `AdMobService.swift`: Google AdMob rewarded ads, inside `#if canImport(GoogleMobileAds)`, so it compiles to nothing
    without the SDK. The reward is granted only from the network's "user earned reward" callback.
  - `AdConsent.swift`: at the first "Watch an ad" tap (never at launch), a short explanation, then Google's consent form
    where the law needs it and Apple's tracking question. "Not now" cancels; nothing is asked again until the next tap.
  - `RewardButton.swift`: the shared button, "Watch an ad: <reward>" with a small TV icon. It pauses the game while the ad
    plays and, if the ad does not finish, says that nothing was lost.
- **Skip ads later**: `AdService.skipsAds` is the seam for a paid "skip ads" option (the Pilot's licence in the growth plan).
  It is `false` now and there is no purchase code. When it is true, each offer becomes a plain "Take it" button with the same
  caps. Add the purchase after the App Store launch, with StoreKit 2 and a Restore Purchases button.

## Switching on AdMob

1. In AdMob (admob.google.com), create the iOS app (it can be linked to the App Store listing later) and one **Rewarded** ad
   unit. Reward settings there do not matter: the game decides the reward.
2. Put the real ids in `BitAirlines/Ads/AdService.swift`, `AdConfig.appID` and `AdConfig.rewardedUnitID` (both marked TODO).
   Until then Google's public test ids are used, which always show a test ad and never pay. Never tap your own live ads:
   add your phone as a test device in AdMob instead.
3. In AdMob, Privacy and messaging: create and publish a **GDPR message** (EU, UK, Switzerland) and, if wanted, the US state
   regulations message. Also add the **IDFA explainer** only if you want Google's screen; the game already explains first.
4. In AdMob, Blocking controls: set the maximum ad content rating to **G**.
5. Make `app-ads.txt` from AdMob (Apps, app-ads.txt) and put it at the root of the developer website listed in App Store
   Connect.
6. Generate the project with the SDK: `BIT_ADS=1 ruby tools/generate_xcodeproj.rb` (works together with `BIT_CLOUD=1`). This
   adds the Google Mobile Ads 12 and UMP 3 Swift packages, `GADApplicationIdentifier`, the tracking question text and the
   SKAdNetwork ids (Google's `cstr6suwn9.skadnetwork`; add others in `SKADNETWORK_IDS` if mediation is added). Without
   `BIT_ADS=1` the build is exactly as before and shows the stand-in ad.
7. Update the App Privacy label, privacy policy and age rating (docs/app-store.md, section 5).

The CI builds without `BIT_ADS`, so it never needs the SDK. Note that `AdMobService.swift` and the consent code have not been
compiled yet (there is no SDK in CI): the first `BIT_ADS=1` build on a Mac may need small fixes if Google renamed something.

## Never

- An ad that plays without a tap, or between screens (interstitials).
- A reward the game cannot be finished without.
- Selling aircraft, levels or cash for real money (pay-to-win is the top complaint in the genre).
- Energy timers or waits invented to sell skips.
