---
name: bitairlines-design
description: Design rules and balance for Bit Airlines, the 8-bit airline management game: the start (a bush airline in a remote region), how demand, fares, costs, schedules, issues and certificate levels work, what the player controls and what runs on its own, and how to change a balance number safely (prototype in tools/sim, then Tuning.swift, then the port tests). Use before changing any game rule, number, aircraft, airport rule, progression step or screen flow, even if the request does not mention balance.
---

# Bit Airlines: design

An iPhone game (landscape, 8-bit pixel art). You start a small airline in a remote region with a used Cessna Caravan, Twin Otter or DC-3, and grow it into a world carrier flying jets into big hubs.
Pocket Planes feel, AirlineSim realism. The aircraft fly your routes on their own; the game stops when something needs you.

## The pillars

1. **Automation with pauses.** Aircraft cycle their routes forever. `World.advance` stops when an issue that pauses the game is raised (breakdown, out of money). The player picks the policy: Never, Problems (default), Everything.
2. **Your airline, on every aircraft.** Name, 2 or 3 letter code, a 16 x 16 pixel logo, three colours from a 32-colour palette and a paint scheme. The livery is applied to every aircraft sprite (logo on the tail). A single aircraft may wear a special livery.
3. **Real world, small start.** 1,295 real airports in 196 countries and territories (OurAirports), one per area so the map stays clean: kept airports are 250 km apart (cities of 5 million or more 180 km, small places near the 10 start regions 130 km), remote towns stay because nothing is near them, the rest are retired but still load for old saves (`tools/data/declutter.py`), populations from GeoNames. Ten remote start regions (`StartRegions`). Bush strips are gravel; big hubs need big certificate levels.
4. **Right plane for the route.** A Caravan beats a Twin Otter on a thin route, a Twin Otter beats a Caravan on a busy one, jets only pay on big markets. This must stay true (`CalibrationTests` checks it).

## How money works (all numbers in `CoreWorld/Tuning.swift`)

- **Demand** (`Demand.swift`): people per day between two airports = `K x sqrt(propensity A x propensity B) x sqrt(pop A^(7/8) x pop B^(7/8)) x distance share / 365`. Propensity comes from the country's wealth tier and is up to 4 times higher for a fly-in community (`isolation`). Fitted to real routes (Sydney-Melbourne, London-New York, Inuvik-Yellowknife); `tools/sim/demand_proto.py` prints the fit.
- **Fares**: a distance table, scaled by 0.85, plus up to 110% for isolated ends. The player sets a multiplier 0.5 to 2.0 per route; fares above 1 lose passengers by `(1/m)^1.5`.
- **Freight**: fly-in communities need food and parts. Freight demand follows the people at the destination, much higher when isolated.
- **Costs per leg** (`LegCost.swift`): fuel (avgas for pistons, jet fuel otherwise, +35% at small remote fields), crew per block hour, maintenance per block hour (grows with age and wear), landing fee per tonne by airport size, navigation fee by distance and weight, per-passenger handling. Fixed daily cost per aircraft and a head office that grows with level.
- **Schedule**: each route has a frequency (departures per day each way). Aircraft wait for the next slot, so the schedule matches demand. `RoutesScreen` tells the player how many aircraft a schedule needs.
- **Competition**: in markets with a catchment above 1.5 million a newcomer wins a small share (up to 50% with reputation and frequency). Remote markets have no competitors.
- **Wear and issues**: condition falls with flying; below 55 an aircraft goes in for a check. Breakdowns are rare and rise with wear. Weather closes remote airports for 1 to 3 days. Running out of money: overdraft notice, then bankruptcy after 14 days.

## Progression

Certificate level 1 to 7 (`Progression.swift`): needs lifetime revenue and reputation, plus a fee. Level unlocks aircraft (`AircraftType.level`) and airport size (`requiredLevel(for:)` by catchment population). Operating in another country needs a permit (price grows with the country's wealth). Level 1 bush, 2 commuter, 3 regional, 4 regional jets, 5 narrowbody mainline, 6 widebody, 7 jumbo.

## Changing a number

1. Change it in the Python prototype (`tools/sim/demand_proto.py` or `route_proto.py`) and look at the output.
2. Change `Tuning.swift` to match, bump `WorldInfo.rulesVersion`.
3. Update the expected numbers in `EconomyPortTests` (they come from the prototype), and read the `CALIBRATION` lines in the CI log (`git show origin/ci-logs-core:core-test.log`) to see what a year of flying earns.

Target pacing: a used aircraft on a good route repays itself in 2 to 4 game years; a single starter aircraft earns a few hundred thousand dollars a year.

## Voice

Plain and specific, like a pilot talking. No hype, no exclamation marks, no em dashes, ASCII only (the pixel font has no accents). Money as `$1.2M`, distances in km, runway in ft (the aviation habit).
