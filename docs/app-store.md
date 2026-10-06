# App Store: setup and compliance

What has to be true before Pixel Props goes to the App Store, and how to switch on iCloud and Game Center.

## 0. Before every App Store or TestFlight build

The project generator's defaults are for testing on your own phone. A store build needs these, in this order:

1. **Paid team and iCloud, Game Center.** `BIT_CLOUD=1` (section 1). Without it the build has no iCloud saves and no
   Game Center, so the store listing must not mention them (docs/store-listing.md says which lines to drop).
2. **Ads, one of two ways.**
   - Without AdMob (no `BIT_ADS`): nothing to do. The stand-in "AD PLACEHOLDER" shows only in Debug builds (Xcode Run);
     an Archive is a Release build, so every Watch an ad button is hidden (`AdConfig.placeholderWithoutSDK`).
   - With AdMob (`BIT_ADS=1`): replace Google's test ids in `BitAirlines/Ads/AdService.swift`, `AdConfig.appID` and
     `AdConfig.rewardedUnitID` (both marked TODO), with the real ones from AdMob. The test ids contain `3940256099942544`:
     a build with them shows test ads and earns nothing. Xcode shows a warning on every Release build with AdMob as a
     reminder; delete it (it sits under `AdConfig`) once the real ids are in. Then do section 5.
3. **Privacy policy.** Put the real address in `BitAirlines/App/AppLinks.swift` (`AppLinks.privacyPolicy`, marked TODO,
   now a placeholder) and the same address in App Store Connect. The page must be live before review.
4. **Version.** `MARKETING_VERSION` in `tools/generate_xcodeproj.rb` is still `0.1.0`: set it to `1.0.0` for the first
   upload, and raise `CURRENT_PROJECT_VERSION` (the build number) for every upload.
5. Archive with the generated project: `BIT_CLOUD=1 ruby tools/generate_xcodeproj.rb` (add `BIT_ADS=1` when ads go live).

## 1. Paid developer account first

iCloud and Game Center cannot be signed by a free personal team, so they are off in the generated project.
After joining the Apple Developer Program ($99 a year):

1. In `tools/generate_xcodeproj.rb`, set `DEVELOPMENT_TEAM` to the paid team ID and `CLOUD_FEATURES = true`
   (or run `BIT_CLOUD=1 ruby tools/generate_xcodeproj.rb`).
2. In Xcode, Signing & Capabilities should then show iCloud and Game Center from `Support/BitAirlines.entitlements`.
3. On developer.apple.com, Identifiers: make sure the app ID `ca.amaruq.bitairlines` has iCloud (with the container
   `iCloud.ca.amaruq.bitairlines`) and Game Center ticked. Automatic signing usually does this for you.
4. The bundle ID becomes permanent after the first upload. Change it now if you want a different one (then also change the
   container ID in `Support/BitAirlines.entitlements`, `BitAirlines/App/CloudSaves.swift` and the IDs in `GameCenter.swift`).

## 2. iCloud saves

- Code: `BitAirlines/App/CloudSaves.swift` (the iCloud folder) and `SaveStore.syncWithCloud` (newest copy wins, judged by the
  `savedAt` stamp inside each save).
- A save is copied to iCloud at most every 3 minutes while playing, and always when the player leaves the game or the app goes
  to the background. The title screen pulls newer copies from other devices.
- Players can turn it off: Settings, "Keep saves in iCloud".
- Without the entitlement (a build made without `BIT_CLOUD=1`) or with iCloud signed out, nothing happens and saves stay
  on the phone. The Settings toggle still shows, with a line saying what it does and that it needs iCloud Drive.

## 3. Game Center

Create these in App Store Connect (your app, Services, Game Center). The IDs must match `BitAirlines/App/GameCenter.swift`.

| Kind | ID | Name | Notes |
|---|---|---|---|
| Leaderboard (classic, high score, integer) | `ca.amaruq.bitairlines.revenue` | Lifetime revenue | Formatted as money |
| Leaderboard (classic, high score, integer) | `ca.amaruq.bitairlines.fleet` | Fleet size | |
| Leaderboard (classic, high score, integer) | `ca.amaruq.bitairlines.goals` | Weekly goals met | One game's count |
| Achievement | `ca.amaruq.bitairlines.firstroute` | First route | |
| Achievement | `ca.amaruq.bitairlines.tenaircraft` | Ten aircraft | |
| Achievement | `ca.amaruq.bitairlines.level2` ... `level7` | Commuter ... Jumbo operator | One per certificate level |
| Achievement | `ca.amaruq.bitairlines.scenario.freezeUp` (and the other scenario ids) | Scenario medal | One per scenario |
| Leaderboard (classic, high score, integer) | `ca.amaruq.bitairlines.stamps` | Dispatch stamps | Daily dispatches flown in one game (one per real day at most) |
| Achievement | `ca.amaruq.bitairlines.airports10` | Ten airports | Landed at 10 airports (Logbook) |
| Achievement | `ca.amaruq.bitairlines.airports50` | Fifty airports | Landed at 50 airports |
| Achievement | `ca.amaruq.bitairlines.airports250` | 250 airports | Landed at 250 airports |
| Achievement | `ca.amaruq.bitairlines.types10` | Ten types | Flown 10 aircraft types |

Each achievement needs a 512 x 512 or 1024 x 1024 image and a short description. Scores go up every 5 minutes of play and
when the player leaves the game. The title screen shows a Leaderboards button once the player is signed in. Without
`BIT_CLOUD=1` there is no Game Center entitlement, the button never shows and nothing is reported.

## 3b. In-App Events (seasonal events)

The game has a calendar of seasonal events on the real date (`AirlineCore/Sources/CoreWorld/SeasonalEvents.swift`). Submit each
one as an In-App Event in App Store Connect (your app, In-App Events) a few weeks before it starts, so it shows on the App
Store. Badge: Special Event, for all six. Priority: normal. Each event unlocks its own paint scheme for flying 3 event jobs
while it runs.

| Event | Dates (every year) | What it does in the game |
|---|---|---|
| Lunar New Year | 7 days either side of Lunar New Year's day (table in the code, to 2040) | More passengers on every route |
| Spring break | 15 to 31 March | More passengers to the coast, islands and lakes |
| Summer peak | 11 to 31 July | Even more passengers to the coast, islands and lakes |
| Harvest freight | 22 September to 12 October | More freight on every route |
| Festival season | 28 October to 10 November | A few more passengers and a little more freight |
| Holiday parcels | 4 to 23 December | Much more freight on every route |

Short description for each (30 characters or fewer), for example "Fly the holiday parcels". Use a screenshot of the
event's paint scheme on an aircraft. Keep the text plain: what the event is and what you can earn.

## 4. Compliance checklist

| Item | Status |
|---|---|
| Privacy manifest (`BitAirlines/Resources/PrivacyInfo.xcprivacy`) | Done: no tracking, no data collected, UserDefaults reason CA92.1 |
| `ITSAppUsesNonExemptEncryption` = NO | Done (in the project generator) |
| Save when the app goes to the background | Done (`RootView`, scene phase) |
| Privacy policy URL in App Store Connect | To do: App Store Connect needs one even when nothing is collected. One page on any site is enough |
| Privacy policy link inside the app (guideline 5.1.1(i)) | Done: Settings, Privacy card, and Credits. To do: the real address in `AppLinks.privacyPolicy` (now the placeholder `https://lontraindustries.com/privacy`) |
| App Privacy label | "Data Not Collected" while AdMob is off. It must change in the same release that switches AdMob on: section 5 |
| Age rating questionnaire | To do: likely 4+ without ads. With ads, answer yes to advertising and set AdMob's content filter to G (section 5) |
| Real aircraft and maker names (Boeing, Airbus, Cessna, De Havilland and others) | Open decision under guideline 5.2.1 (third-party trademarks). The Credits now say the names belong to their owners and the game is not endorsed by them, and no maker logos are used. Either keep that (and add the same sentence to the description), or rename to invented makers before release. Record the choice here |
| Real airline codes used as examples ("AA") | Done: the new-airline flow uses "ZZ" |
| Launch screen | Set a background colour matching `Theme.background` to avoid a white flash |
| "Declare bankruptcy" | Done: asks to confirm first |
| iPad | iPhone only. App Review may run it in the iPad compatibility window: test that |
| Build with the current Xcode and iOS SDK | Required for upload |
| Version | To do: `MARKETING_VERSION` is `0.1.0` in `tools/generate_xcodeproj.rb`. Set `1.0.0` and raise the build number for each upload |
| In-app purchases (if added) | StoreKit 2, a Restore Purchases button, prices shown before buying |
| iCloud and Game Center | Only with `BIT_CLOUD=1` (section 1). A build without it must not advertise them |
| Ads | Built in; AdMob itself only with `BIT_ADS=1` (docs/rewarded-ads.md). Without the SDK, the stand-in ad shows only in Debug builds; Release builds hide every ad button. With the SDK, the real ids must replace Google's test ids before the store build (section 0). Every ad is optional and asked for by a tap |

## 5. When ads go live

Switching on AdMob (`BIT_ADS=1`, real ids in `AdConfig`) changes what the App Store must be told. Check Google's current page
"Prepare for Apple's App Store data disclosure requirements" before submitting; it lists what the SDK collects.

**App Privacy label** (App Store Connect, App Privacy): no longer "Data Not Collected". Declare what the Google Mobile Ads
SDK collects, as of 2026:

| Data type | Used for | Linked to the player | Used to track |
|---|---|---|---|
| Identifiers: Device ID (the advertising id, only after "Allow") | Third-party advertising | No | Yes |
| Usage Data: Advertising Data | Third-party advertising, analytics | No | Yes |
| Usage Data: Product Interaction | Third-party advertising, analytics | No | No |
| Location: Coarse Location (from the IP address) | Third-party advertising | No | No |
| Diagnostics: Crash Data, Performance Data, Other Diagnostic Data | Analytics | No | No |

The game itself still collects nothing: saves stay on the phone and in the player's own iCloud.

**Privacy manifest**: the app's own `PrivacyInfo.xcprivacy` stays as it is. The Google Mobile Ads and UMP packages ship their
own manifests, which Xcode merges into the privacy report (Product, Archive, then Generate Privacy Report). Read that report
before uploading.

**Privacy policy**: must now say that ads are shown by Google AdMob, what it collects (the table above), that tracking is
only with the player's permission, and link to Google's policy (policies.google.com/technologies/ads).

**Age rating**: answer that the app shows ads. In AdMob, set the maximum ad content rating to G (Blocking controls, Content
rating) so ads suit the 4+ or 9+ rating, and leave "tag for child-directed treatment" unset unless the game targets children
(it does not; if the owner wants under-13 players, Google's Families policy and an age question apply first).

**Tracking question (ATT)**: the words are set in `tools/generate_xcodeproj.rb` (`TRACKING_TEXT`). The game asks it at the
first "Watch an ad" tap, after its own short explanation, never at launch. The explanation has a single Continue button that
always leads on to Google's form and then Apple's question, where the player can say no: App Review rejects a message before
the tracking question that lets the player skip it ("Not now"). The ad stays optional because the player only reaches the
explanation by tapping Watch an ad. App Review checks that the app works the same after "Ask App Not to Track".

**Consent in the EU, UK and Switzerland**: create a GDPR message in AdMob (Privacy and messaging) and publish it. The game
shows it at the first "Watch an ad" tap through Google's UMP form. Players change or withdraw that consent with "Ad privacy
choices" in Settings (the Privacy card), which opens Google's privacy options form. The button shows only when Google says
it is needed (`privacyOptionsRequirementStatus == .required`).

**Before submitting with ads, also check**: the App Privacy table above against Google's "App Store data disclosure" page
and Xcode's privacy report (the SDK may also read the vendor id without permission), and Google's current SKAdNetwork list
(only Google's own id is in `SKADNETWORK_IDS` now).
