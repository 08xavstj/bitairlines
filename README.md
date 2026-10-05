# Bit Airlines

An iPhone airline management game in 8-bit pixel art, played in landscape. Start with one Twin Otter at a remote strip, design your own airline (name, logo,
colours, liveries), and grow it into a world network that flies jets into major hubs. The aircraft fly your routes on their own; the game pauses when something
needs you. Working title.

Status: foundation. The pipeline builds and tests on every push (see CI below); the game itself is being built stage by stage, see `docs/roadmap.md` once it exists.

## Layout

| Path | What |
|---|---|
| `AirlineCore/` | Pure-Swift game logic package (math, catalog data, world and economy rules). No UI or persistence imports; deterministic. Swift 6 strict. |
| `BitAirlines/` | The iPhone app (SwiftUI), landscape. Swift 5 language mode on purpose (see `CLAUDE.md`). |
| `BitAirlinesTests/` | App tests. |
| `tools/` | `generate_xcodeproj.rb` (the Xcode project is generated), `check-core-purity.sh`, `ci_publish_logs.sh`, data pipeline scripts. |
| `.github/workflows/ci.yml` | macOS build and test on every push. |
| `CLAUDE.md` | How the local agent and Claude share this project. |

Sibling project: [Ring Legacy / BoxingManager](https://github.com/08xavstj/BoxingManager), whose stack and pixel look this game follows.

## Commands (on a Mac)

```bash
swift test --package-path AirlineCore
tools/check-core-purity.sh AirlineCore/Sources
ruby tools/generate_xcodeproj.rb          # then: open BitAirlines.xcodeproj
```

## CI without a Mac

Development happens on Windows, so GitHub Actions is the compiler. After a push, trimmed logs are on the `ci-logs` branch:

```bash
git fetch origin ci-logs && git show origin/ci-logs:status.txt
git show origin/ci-logs:core-test.log      # also: app-build.log, app-test.log, generate.log, purity.log
```
