# Roadmap

Status as of the first push. "Tested" means a test runs in CI; "written" means the code exists but has not run on a phone yet.

## Done

| Area | State |
|---|---|
| Airport data | 4,933 real airports, one per city or town (remote communities kept), named by place, 233 countries, catchment populations, runway and surface. Tested. |
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

## Next

1. **Run it on a phone and fix what looks wrong.** The UI has been compile-checked and screenshotted in a simulator, not played. Expect layout and feel problems, and listen to the sound.
2. **Contracts and jobs.** Medevac, mail, charter offers, a subsidised essential service for a village; a job board with deadlines and reputation.
3. **Airport investment in remote places.** Lighting, gravel to paved, fuel depot, hangar base.
4. **Easy, Realism and Sandbox modes, and a perk to pick at each certificate level.** Easy ignores runway, surface and weather limits; Realism sells fuel only where it is really sold; Sandbox has no money limit.
5. **Competitor airlines** as real entities in the world instead of an average market share.
6. **Hubs and connecting passengers.**
7. **Seasons and time of day.** Daylight limits on unlit strips, polar night, holiday peaks.
8. **Maintenance policy** (own hangar, planned checks), **crew** as a resource, **leasing**.
9. **App Store work.** Name check, privacy page, icon polish, TestFlight.

The reasoning and the other ideas considered are in [feature-research.md](feature-research.md).

## Known limits

- Passengers are per leg (a milk run A-B-C does not carry A-to-C passengers through B).
- The market share model is an average; there are no named competitors yet.
- Population per airport comes from nearby towns, so a few places (for example Lukla) have more people than they should.
- Demand does not change with the economy, news or events yet.
