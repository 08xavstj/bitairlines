# Pixel Props

The game's name (it was "Bit Airlines" while in development; the code, folders and project still use BitAirlines inside).

An iPhone airline management game in 8-bit pixel art, played in landscape. Start a small airline at a remote strip with one
used bush plane (whichever level 1 type can land at your home airport and fits the budget: a Cessna Caravan, Twin Otter, DC-3
and others), design your own airline (name, code, logo, colours, liveries), and grow it into a world network that flies jets
into major hubs. The aircraft fly your routes on their own; the game pauses when something needs you.

What is in the game (the store copy is in `docs/store-listing.md`, the full list in `docs/roadmap.md`):

- 1,295 real airports on a clean world map, from island and jungle strips to the biggest hubs.
- Routes that fly themselves on a schedule, with forecasts, fares, freight and competition.
- More than 50 aircraft types, with floats, skis and other kits; rare finds and restorations.
- Jobs between routes (medevac, mail, charters), a daily dispatch, seasonal events and weekly goals.
- Certificate levels 1 to 7, perks, staff, marketing, bases, hubs, slots, pilots and rival airlines.
- Optional rewarded ads only (never forced), chiptune sound made on the device, and scenarios with medals.

Status: playable, being polished for the App Store (`docs/app-store.md` lists what is left). Logic is tested in CI on every
push; the app builds and tests on macOS when asked (see CI below).

## Layout

| Path | What |
|---|---|
| `AirlineCore/` | Pure-Swift game logic package (math, catalog data, world and economy rules). No UI or persistence imports; deterministic. Swift 6 strict. |
| `BitAirlines/` | The iPhone app (SwiftUI), landscape. Swift 5 language mode on purpose (see `CLAUDE.md`). |
| `BitAirlinesTests/` | App tests. |
| `tools/` | `generate_xcodeproj.rb` (the Xcode project is generated), `check-core-purity.sh`, `ci_publish_logs.sh`, data pipeline scripts. |
| `.github/workflows/core.yml` | Linux: purity check and `swift test` for `AirlineCore` on every push. |
| `.github/workflows/app.yml` | macOS: generate the project, build and test the app, only on `[app]` commits or by hand. |
| `CLAUDE.md` | How the local agent and Claude share this project. |

Sibling project: [Ring Legacy / BoxingManager](https://github.com/08xavstj/BoxingManager), whose stack and pixel look this game follows.

## Commands (on a Mac)

```bash
swift test --package-path AirlineCore
tools/check-core-purity.sh AirlineCore/Sources
ruby tools/generate_xcodeproj.rb          # then: open BitAirlines.xcodeproj
```

A store build needs more than the defaults (`BIT_CLOUD=1`, real AdMob ids with `BIT_ADS=1`, the privacy policy address, the
version): the steps are in `docs/app-store.md`, section 0.

## CI without a Mac

Development happens on Windows, so GitHub Actions is the compiler.

- **Core** workflow (Linux, every push): purity check and `swift test` for `AirlineCore`. Logs: branch `ci-logs-core`.
- **App** workflow (macOS, only when the commit message contains `[app]`, or run by hand): generates the project, builds and tests the app on a simulator. Logs: branch `ci-logs-app`.
  macOS minutes are ten times as expensive as Linux minutes on a private repo, so batch app changes before building.

Read a result without a GitHub login:

```bash
git fetch origin ci-logs-core && git show origin/ci-logs-core:status.txt
git show origin/ci-logs-core:core-test.log       # app: ci-logs-app, app-test.log, generate.log
```
