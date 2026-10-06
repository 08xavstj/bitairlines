# Roadmap

Status in October 2026. "Tested" means a test runs in CI; "written" means the code exists but has not run on a phone yet.

## Done

| Area | State |
|---|---|
| Airport data | 2,427 real airports on the map: big cities and remote places (road towns near a city are retired, see tools/data/declutter.py, but still load for old saves), named by place, 216 countries, catchment populations, runway and surface. Tested. |
| World map data | 2880 x 1440 land mask from Natural Earth, decoded in Core. Tested. |
| Aircraft | 52 real models from the Cessna 172 and DC-3 to the A380, with floatplane variants. Tested. |
| Economy | Demand fitted to real traffic, fares, freight, leg costs, schedules, competition. Python prototypes and Swift port agree. Tested. |
| Simulation | Aircraft fly routes by schedule slot, boarding buckets, wear, breakdowns, weather, loans, overdraft, certificates. Deterministic, save and resume tested. |
| Pausing | Issues stop the game by policy (Never, Problems, Everything). Tested. |
| Airline identity | Name, code, 16 x 16 logo, three palette colours, six paint schemes, special liveries per aircraft. Sprites and recolouring written; tests run on the simulator. |
| App | Title, new airline wizard with logo editor, map with route planning, fleet, routes, hangar, money, inbox, airline screens. Written. |
| Route forecast | Steady-state profit per day, aircraft needed and payback for any route and aircraft, within 10 percent of a simulated year. The planner ranks the aircraft that pay; route cards and the aircraft sheet show the outlook. Tested. |
| Sound | Chiptune effects and two music loops synthesised on the device, with a settings toggle for effects and music and three volume levels. Synth and cue logic tested; not yet heard on a phone. |
| Guided first route | Five steps derived from the world (open a route, assign the aircraft, start the clock, watch it fly, review), a coach strip and a highlight on the next control. Tested. |
| Aircraft art | Windscreens, swept wings with a dark leading edge, engine pods with intakes, propeller discs, wheels. Regenerated from `tools/art/aircraft.py`. |
| Game modes | Easy, Normal, Realism (fuel only at real fuel stops) and Sandbox, chosen when the airline is founded. Tested. |
| Perks | Pick one of three at each certificate level (fuel deal, quick turns, good name and six more). Tested. |
| Fuel market | Daily price drift and oil shocks, a price chart, fuel bought ahead used first. Tested. |
| Service and punctuality | Basic, standard or premium service per route; an on-time record that feeds reputation. Tested. |
| Bases | Fuel depot, hangar, runway lights, longer runway, paving and hub terminal at any airport served. Home apron scene with a departures board. Tested (scene not yet seen on a phone). |
| Kits | Floats, amphibious floats, wheel-skis, gravel kit, STOL kit, freighter conversion. Lakes freeze in winter; skis land on the ice. Tested. |
| Daylight | Unlit strips are open only in daylight plus twilight, so polar winter cuts the schedule until lights are built. Tested. |
| Job board | Medevac, mail, fuel drums, crew changes, lodge charters, surveys and freight near the network, with deadlines; the aircraft returns to its route after. Tested. |
| Events | Forest fire evacuations, early thaw, volcanic ash, film crew, winter games (with a sponsorship offer), oil shock, mining boom. Tested. |
| Hubs | Passengers change planes at a hub terminal between the airline's routes. Tested. |
| Slots | Busy airports (certificate level 3 and up) ration daily departures; slots are bought and sold. Tested. |
| Rival airlines | Named computer airlines with routes and fares; they answer fare cuts and move into busy routes; a rankings table. Tested. |
| Pilots | Pilots with ratings, hours, salaries, sickness and type courses; spares step in; automatic hiring for new aircraft. Tested. |
| Scenarios | Six short games with a goal, a deadline and medals; best medals kept on the phone. Tested. |

## Next

1. **Run it on a phone and fix what looks wrong.** Everything above is compile-checked, tested in CI and screenshotted in a simulator, not played. Expect layout and balance problems.
2. **Balance pass** with the added systems together (pilot pay, rivals, daylight and events change what a route earns).
3. **Holiday peaks and the economy**: demand that moves with events beyond the current ones.
4. **Leasing** aircraft instead of buying.
5. **App Store work.** Name check, privacy page, icon polish, TestFlight.

The reasoning and the other ideas considered are in [feature-research.md](feature-research.md). Eras were considered and left out.

## Known limits

- On one route, passengers ride a single leg (a milk run A-B-C does not carry A-to-C passengers through B); between routes they connect only at a hub terminal.
- Rival airlines are estimated, not simulated aircraft by aircraft.
- Population per airport comes from nearby towns, so a few places (for example Lukla) have more people than they should.
- Demand changes with events near the network, but not yet with the wider economy.
