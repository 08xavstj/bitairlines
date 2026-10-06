# Roadmap

Status as of the first push. "Tested" means a test runs in CI; "written" means the code exists but has not run on a phone yet.

## Done

| Area | State |
|---|---|
| Airport data | 6,432 real airports, 233 countries, catchment populations, runway and surface. Tested. |
| World map data | 2880 x 1440 land mask from Natural Earth, decoded in Core. Tested. |
| Aircraft | 52 real models from the Cessna 172 and DC-3 to the A380, with floatplane variants. Tested. |
| Economy | Demand fitted to real traffic, fares, freight, leg costs, schedules, competition. Python prototypes and Swift port agree. Tested. |
| Simulation | Aircraft fly routes by schedule slot, boarding buckets, wear, breakdowns, weather, loans, overdraft, certificates. Deterministic, save and resume tested. |
| Pausing | Issues stop the game by policy (Never, Problems, Everything). Tested. |
| Airline identity | Name, code, 16 x 16 logo, three palette colours, six paint schemes, special liveries per aircraft. Sprites and recolouring written; tests run on the simulator. |
| App | Title, new airline wizard with logo editor, map with route planning, fleet, routes, hangar, money, inbox, airline screens. Written. |

## Next

1. **Run it on a phone and fix what looks wrong.** The UI has been compile-checked, not played. Expect layout and feel problems.
2. **Route forecast.** Show expected profit per day for a route and aircraft before committing (port `tools/sim/route_proto.py` to Core).
3. **Aircraft art pass.** The sprites are procedural and readable but plain; give each family a hand-polished look.
4. **Sound.** Chiptune synth and effects (Ring Legacy has `ChipSynth`).
5. **Competitor airlines** as real entities in the world instead of an average market share.
6. **Contracts and events.** Medevac, mail, charter offers; events with choices in remote regions.
7. **Seasons and time of day.** Daylight limits on unlit strips, polar night, holiday peaks.
8. **Tutorial** for the first hour, and a guided first route.
9. **Maintenance policy** (own hangar, planned checks), **crew** as a resource, **leasing**.
10. **App Store work.** Name check, privacy page, icon polish, TestFlight.

## Known limits

- Passengers are per leg (a milk run A-B-C does not carry A-to-C passengers through B).
- The market share model is an average; there are no named competitors yet.
- Population per airport comes from nearby towns, so a few places (for example Lukla) have more people than they should.
- Demand does not change with the economy, news or events yet.
