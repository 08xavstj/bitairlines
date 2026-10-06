# Roadmap

Status in October 2026. "Tested" means a test runs in CI; "written" means the code exists but has not run on a phone yet.

## Done

| Area | State |
|---|---|
| Airport data | 1,295 real airports on the map in 196 countries and territories, one per area: 250 km apart (cities of 5 million or more 180 km; small places within 300 km of a start region 130 km, so a new airline has places to fly), remote towns kept because nothing is near them (tools/data/declutter.py); the rest are retired but still load for old saves. Seven small Caribbean island strips (St Barths, Saba, Statia, Nevis, Barbuda, Montserrat, Virgin Gorda) were brought back so island starts have somewhere to fly. Named by place, catchment populations, runway and surface. Tested. |
| World map data | 2880 x 1440 land mask from Natural Earth, decoded in Core. Tested. |
| Aircraft | 52 real models from the Cessna 172 and DC-3 to the A380, with floatplane variants. Tested. |
| Economy | Demand fitted to real traffic, fares, freight, leg costs, schedules, competition. Python prototypes and Swift port agree. Tested. |
| Simulation | Aircraft fly routes by schedule slot, boarding buckets, wear, breakdowns, weather, loans, overdraft, certificates. Deterministic, save and resume tested. |
| Pausing | Issues stop the game by policy (Never, Problems, Everything). Tested. |
| Airline identity | Name, code, 16 x 16 logo, three palette colours, six paint schemes, special liveries per aircraft. Sprites and recolouring written; tests run on the simulator. |
| App | Title, new airline wizard with logo editor, map with route planning, fleet, routes, hangar, money, inbox, airline screens. Written. |
| Route forecast | Steady-state profit per day, aircraft needed and payback for any route and aircraft, within 10 percent of a simulated year. The planner ranks the aircraft that pay; route cards and the aircraft sheet show the outlook. Tested. |
| Sound | Chiptune effects and two music loops synthesised on the device, with a settings toggle for effects and music and three volume levels. Synth and cue logic tested; not yet heard on a phone. |
| Guided first route | Eleven steps derived from the world: the first route (open a route, assign the aircraft, start the clock, watch it fly, review), then a short tour (Money, Inbox, Hangar, a second route, Jobs, the certificate level). A coach strip and a highlight on the next control. Tested. |
| Aircraft art | Windscreens, swept wings with a dark leading edge, engine pods with intakes, propeller discs, wheels. Regenerated from `tools/art/aircraft.py`. |
| Game modes | Easy, Normal, Realism (fuel only at real fuel stops) and Sandbox, chosen when the airline is founded. Tested. |
| Perks | Pick one of three at each certificate level (fuel deal, quick turns, good name and six more). Tested. |
| Fuel market | Daily price drift and oil shocks, a price chart, fuel bought ahead used first. Tested. |
| Service and punctuality | Basic, standard or premium service per route; an on-time record that feeds reputation. Tested. |
| Bases | Fuel depot, hangar, runway lights, longer runway, paving and hub terminal at any airport served. Home apron scene with a departures board. Tested (scene not yet seen on a phone). |
| Kits | Floats, amphibious floats, wheel-skis, gravel kit, STOL kit, freighter conversion. Lakes freeze in winter; skis land on the ice. Tested. |
| Daylight | Unlit strips are open only in daylight plus twilight, so polar winter cuts the schedule until lights are built. Tested. |
| Job board | Medevac, mail, fuel drums, crew changes, lodge charters, surveys and freight near the network, with deadlines; the aircraft returns to its route after. Each job says which of your aircraft can fly it (or why none can), with a "Jobs I can fly" filter on by default. Tested. |
| Positioning flights | An empty aircraft that cannot reach a route or a job pickup in one go flies there through stops it can use (fuel stops in Realism), planned by a shortest-path search over the map airports. Picking an aircraft for a job or a route lists the ones that can do it first, with the empty flight each needs, and greys the rest with the reason. The route planner marks a leg none of your aircraft can fly and offers a stop in between. Tested in Core; app not yet seen on a phone. |
| Events | Forest fire evacuations, early thaw, volcanic ash, film crew, winter games (with a sponsorship offer), oil shock, mining boom. Tested. |
| Hubs | Passengers change planes at a hub terminal between the airline's routes. Tested. |
| Slots | Busy airports (certificate level 3 and up) ration daily departures; slots are bought and sold. Tested. |
| Rival airlines | Named computer airlines with routes and fares; they answer fare cuts and move into busy routes; a rankings table. Tested. |
| Pilots | Pilots with ratings, hours, salaries, sickness and type courses; spares step in; automatic hiring for new aircraft. Tested. |
| Scenarios | Six short games with a goal, a deadline and medals; best medals kept on the phone. Tested. |
| Island starts | A home on a small island nation (Sint Maarten, Antigua, St Kitts) starts with permits for the countries within 250 km, so the first route has somewhere to go. Tested. |
| Weekly goals | A game-week goal (people, freight, flights or revenue, sometimes tied to a place) and a real-week goal (Monday to Sunday on the real calendar), each with a bonus. Tested. |
| Daily dispatch and stamps | One special charter per real day; flying it earns a stamp, and every 7 stamps unlock a classic livery and a rare find. Tested. |
| Seasonal events | Six events on the real calendar (Lunar New Year to holiday parcels) that lift demand, add event jobs and give an event livery. Tested. |
| Rare finds and restoration | Low-hours aircraft, heritage classics and barn-find projects on the used market; a project is restored in the hangar. Heavy checks every few years. Tested. |
| Logbook | Every type flown, airport landed at and rare find bought, with Game Center achievements for the milestones. Tested; screen written. |
| Staff | Revenue manager (fares each Monday), operations manager (settles breakdowns), fleet planner (moves spare aircraft to routes that earn more, puts parked aircraft to work, sets schedules). Tested. |
| Marketing | Posters, radio and national campaigns: a bigger share of passengers while they run and better-known routes at once. Tested. |
| Growth | Sell a route to a local operator, leave an airport, move the headquarters, trade in an aircraft, suggested routes to bigger cities. Tested. |
| Shared aircraft and spare aircraft | One aircraft can fly up to three routes; spare aircraft move to a route that earns more. Tested. |
| Routes screen | A compact routes list with a detail sheet for each route, planner buttons always in view. Written. |
| Rewarded ads | Eleven optional "Watch an ad" rewards with caps per real day; the stand-in ad in Debug builds, AdMob behind `BIT_ADS=1`, consent and tracking questions at the first tap, "Ad privacy choices" in Settings. Core tested; AdMob code not yet compiled (docs/rewarded-ads.md). |
| Time away | The game catches up one game hour per real minute away, up to three game days (72 real minutes), and shows a "While you were away" summary. Tested. |
| Notifications | One local note for the first thing that will need the player while away, and an optional daily dispatch reminder. Words tested; not yet seen on a phone. |
| Rating prompt | Apple's rating box at most once per version, after a win (first weekly goal, level 2, a scenario medal), never over a decision or right after a loss. Tested. |
| iCloud saves and Game Center | Saves copied to the player's iCloud; four leaderboards (revenue, fleet, goals, stamps) and achievements. Only with `BIT_CLOUD=1` and a paid team (docs/app-store.md). Written, not yet signed. |
| Privacy | Privacy policy link in Settings and Credits (placeholder address until the page exists). Written. |

## Next

1. **Run it on a phone and fix what looks wrong.** Everything above is compile-checked, tested in CI and screenshotted in a simulator, not played. Expect layout and balance problems.
2. **Balance pass** with the added systems together (pilot pay, rivals, daylight and events change what a route earns).
3. **Holiday peaks and the economy**: demand that moves with events beyond the current ones.
4. **Leasing** aircraft instead of buying.
5. **App Store work.** Privacy policy page (and its address in `AppLinks`), icon polish, version 1.0.0, a `BIT_CLOUD=1` build, TestFlight. The steps are in docs/app-store.md, section 0.

The reasoning and the other ideas considered are in [feature-research.md](feature-research.md). Eras were considered and left out.

## Known limits

- On one route, passengers ride a single leg (a milk run A-B-C does not carry A-to-C passengers through B); between routes they connect only at a hub terminal.
- Rival airlines are estimated, not simulated aircraft by aircraft.
- Population per airport comes from nearby towns, so a few places (for example Lukla) have more people than they should.
- Demand changes with events near the network, but not yet with the wider economy.
