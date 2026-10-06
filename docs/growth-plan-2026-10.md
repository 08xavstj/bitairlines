# Growth plan: downloads, daily play, and ads people choose to watch

Research from October 2026 on the most successful idle, tycoon and management games (Idle Miner Tycoon, AdVenture Capitalist,
Egg Inc, Pocket Planes and Trains, Airline Manager 4, Airlines Manager, Mini Metro, Kairosoft, Monopoly Go, Pokemon GO,
Duolingo's streaks, Archero) and on rewarded-ad practice. Numbers marked "vendor" come from ad or analytics companies and are a
direction, not a promise. Sources are at the end.

## 1. Where Bit Airlines stands

Already in the game: routes that fly themselves, a weekly goal, a "while you were away" summary, rare finds, marketing, staff,
rivals, scenarios with medals, the logo and livery editor, iCloud saves and Game Center.

Missing: anything tied to the real calendar (so there is no reason to open the game on a given day), notifications, widgets,
sharing, a rating prompt, localisation, and the ads themselves.

Benchmarks to aim for (GameAnalytics, 16,000 games): median day-1 retention 22%, day-7 about 4%; the top 10% reach 40% and 11 to
12%. Airline Manager reports about 30% day-1; Kolibri reports 75% for Idle Miner Tycoon (company figures).

## 2. What brings players back every day (ranked for this game)

| # | Feature | Impact | Effort | How it works here |
|---|---|---|---|---|
| 1 | First session that pays | High | Low | New airlines start in spring daylight (not polar night), the guided route has full demand for its first month, and a second aircraft or route is affordable within about 10 minutes. Kolibri's biggest churn fix was exactly this ("the second mine shaft"). |
| 2 | Daily dispatch with a streak | High | Medium | One special charter each real day, the same for everyone (picked from the date, no server): a medevac, a fuel-drum run, a lodge charter near your network. Each one flown earns a stamp; 7 stamps (not in a row) unlock a rare find or a classic livery. A Game Center board for the day's best delivery. Rewards are cosmetics and leads, not cash, so the economy holds. |
| 3 | Useful notifications | High | Medium | Ask after the first breakdown ("Tell me when an aircraft needs me"). Because the simulation is deterministic, the game can run a copy forward when you leave and schedule exactly the next real event: a breakdown, an overdraft, a job deadline, the fleet reaching its away limit, today's dispatch. One or two a day at most, each type can be turned off. |
| 4 | Real-week goal | High | Low | Keep the game-week goal and add a Monday-to-Sunday goal on the real calendar, tied to a place ("2 t of freight to Kugluktuk"), with a leaderboard. |
| 5 | Seasonal events | High | Medium | A calendar inside the app, picked by real date: freeze-up mail run (November), holiday parcels (December), spring breakup (April), midnight-sun tours (June). Each brings a limited livery and is submitted to Apple as an In-App Event, which shows on the App Store. |
| 6 | Livery and logo sharing | Medium-high | Low-medium | A pixel postcard of your aircraft in your livery at a real Arctic strip, plus a short code that rebuilds the logo and colours in anyone's game. Every shared code advertises the game (TikTok, Reddit). |
| 7 | Collections | Medium | Low-medium | A logbook of aircraft types flown, a stamp for every airport landed at ("all 33 Nunavut strips"), a gallery of rare finds, each with a Game Center achievement. |
| 8 | Always-visible next step | Medium | Low | One line on the map: "Twin Otter affordable in 9 days", "Level 3 at reputation 20". |
| 9 | Home-screen widget | Medium | Medium | Cash, aircraft in the air, goal progress, today's dispatch, from a small file written when the app goes to the background. |
| 10 | Live Activity for a job | Low-medium | Medium | A medevac shown in the Dynamic Island until it lands. |
| 11 | Regular updates | Medium | Ongoing | Something small every 4 to 6 weeks (a region, aircraft, an event), each nominated to Apple. Pocket Planes only climbed the charts on updates. |

Skip for now: a daily login reward (the dispatch does the same with real play), energy timers, clubs and alliances (they need a
server; revisit after launch).

## 3. What drives downloads

- **Apple featuring.** Editors look for gameplay, art, sound, performance, localisation and accessibility in new apps and
  significant updates. Nominate each release and each seasonal event in App Store Connect 2 weeks to 3 months ahead.
- **The first three screenshots** decide most installs (3 to 6 seconds of attention). Plan in docs/store-listing.md.
- **A 15 to 25 second preview video**: a floatplane leaving Inuvik, the map zooming out to a network, a logo being painted.
  Vendors report +20 to 35% conversion for games, but Apple shows cases where a video lowered it, so A/B test it with Product
  Page Optimization (also test 3 icons).
- **Rating prompt** after a win only (first weekly goal, level 2, a scenario medal), once per version. Never after a loss.
- **Localisation**: the pixel font needs accented letters first; then French, German, Spanish and Brazilian Portuguese. Store
  pages can be localised before the game is.
- **Launch with a seasonal event ready on day one**, so editors have a reason to feature it and players a reason to return.

## 4. Ads people want to watch

The rule from every successful example: the ad is offered at the moment the player wants the reward, the reward is worth more
than 30 seconds, and nothing is ever forced. Placements tied to a moment of need get about 38% of daily players to watch, against
24% for offers between levels (vendor: Unity). Players uninstall over forced, long or broken ads (84% say so, eMarketer).

Rewards scale with the airline ("a profit day" = average daily operating profit over the last 7 game days, at least $2,000), so
they matter at level 1 and level 7 alike. Caps count real days.

| # | Where | Reward | Cap |
|---|---|---|---|
| 1 | While-you-were-away summary | The away profit paid again (up to 3 profit days since breaks pay up to 3 game days; 2 in this plan) | 3 a day |
| 2 | Money screen | Sponsor boost: +25% ticket revenue as a sponsor bonus for 1 game day, stacking to 4 | 4 a day |
| 3 | Aircraft in a check, or a barn find | Finish the check or restoration step now | 3 a day |
| 4 | Weekly goal met | Double the bonus | once a week |
| 5 | Overdraft | A sponsor covers a week of head office | once per overdraft |
| 6 | Breakdown | The mechanic flies in free | once per breakdown |
| 7 | Jobs board | Double one job's pay | once a day |
| 8 | Marketing | A free posters campaign | once per 14 game days |
| 9 | Jobs board | New jobs now | once a day |
| 10 | Rare find | Hold it 7 more days | once per listing |
| 11 | Hangar | A broker's tip: two extra listings this week | once a week |

The sponsor boost pays a bonus rather than doubling income, so the route economics stay honest.

**Revenue estimate** (ad revenue per daily player = share who watch x ads each x eCPM / 1000; vendor inputs):

| Daily players | Low ($0.006 each) | Mid ($0.023) | High ($0.068) |
|---|---|---|---|
| 5,000 | $11k a year | $43k | $125k |
| 50,000 | $110k | $427k | $1.25M |
| 500,000 | $1.1M | $4.3M | $12.5M |

Apple takes no cut of ad revenue. Allow 10 to 25% less for fill rate and the January dip. 500,000 daily players is very rare
for an independent launch; 5,000 to 50,000 is the realistic range for a well-featured niche game.

**Purchases that sit alongside ads (no pay-to-win):**
- Pilot's licence, $6.99 once: every ad offer becomes a plain button with the same caps. Restore Purchases required.
- Livery packs, $1.99 to $2.99 (the special-livery system already supports them).
- Supporter pack, $9.99: the licence plus two liveries.
- Never: a premium currency, cash packs, or aircraft for money.

**Build order:** Google AdMob with its consent tool (UMP) at launch; move to AppLovin MAX with Google bidding past about 10,000
daily players. Consent form first in the EU, UK and Switzerland; ask for tracking (ATT) at the first ad button, after a short
plain explanation, never at launch. Grant rewards only on the network's reward callback. Update the App Privacy label and age
rating when ads go in (docs/app-store.md).

## 5. Names

Checked against the App Store, Google Play and real airlines. "Clear" means no conflict was found in searches; it is not a
trademark clearance, and domains still need checking.

Shortlist:
1. **Floatplane Co.** - names the hook (a bush start), a floatplane makes an instant icon, no conflicts found.
2. **Lontra Air** - ties the airline to the studio (Lontra Industries, the otter splash); lontra is Latin for otter.
3. **Treeline Air** - "north" without real-airline or TV baggage; a pine silhouette icon.
4. **Propwash** - one memorable aviation word, no game found.
5. **Little Props** - cozy and humble, the props grow into jets.
6. **Bit Airlines** - no conflict, has "airline" in it, but the least memorable.

Pair any with the subtitle "Pixel Airline Tycoon" or "Bush Planes to Jumbo Jets": the App Store searches the subtitle too, and
airline, tycoon, idle, plane, airport, pilot and manager are the words players search for in this genre.

Avoid: Pixel Planes and Pocket Airline (NimbleBit's Pocket Planes trademark), Arctic Air (CBC drama), Air North, Otter Air,
Tailwind, Aurora Air and Polar Hop (real airlines), Bush Pilot (crowded), Sprite Air (Coca-Cola).

On the bundle id `ca.amaruq.bitairlines`: Inuvik and Tuktoyaktuk are Inuvialuit communities, and Inuit groups have objected to
southern businesses using Inuit words and symbols. Do not use Inuktitut or Inuvialuktun words as names without Inuvialuit
partners agreeing. The bundle id is mostly hidden, but a neutral one such as `ca.lontra.<game>` avoids the question; it must be
decided before the first App Store upload, after which it cannot change.

## 6. Order of work

1. First session that pays; rating prompt; next-step line. (Small, raise day-1 retention.)
2. Daily dispatch with stamps; real-week place goal; notifications.
3. Rewarded ads (AdMob, consent, the placements above) and the Pilot's licence.
4. Sharing (postcard and code), collections, the widget.
5. Seasonal events calendar and the preview video; then localisation.

## Sources
GameAnalytics benchmarks via GameDevReports; Trophy Games annual report 2023; GameAnalytics and Pangle on Kolibri; GDC 2019
Idle Miner Tycoon deconstruction; Duolingo blog and Econsultancy on streaks; Airship and Pushwoosh on push; PocketGamer.biz and
Mobidictum on Monopoly Go; TouchArcade and Game Developer on Pocket Planes and Trains; Apple's "Getting featured", Product Page
Optimization and In-App Events pages; mobilegamer.biz on Apple editorial; StoreMaven via Sonar on preview video; Distimo via
PocketGamer.biz on localisation; Unity 2024 rewarded ads report via PocketGamer.biz; eMarketer and Unstar on ad complaints;
Appodeal and Business of Apps on eCPM; Juego Studio on ARPDAU; Adjust on ATT opt-in; Google AdMob GDPR and rewarded docs;
AppLovin SKAdNetwork and privacy manifest docs; NimbleBit trademarks (Justia); App Store and Steam listings for the name checks;
CBC, Nunatsiaq News and Smart & Biggar on Inuit cultural appropriation.
