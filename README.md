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

Development happens on Windows, so GitHub Actions is the compiler.

- **Core** workflow (Linux, every push): purity check and `swift test` for `AirlineCore`. Logs: branch `ci-logs-core`.
- **App** workflow (macOS, only when the commit message contains `[app]`, or run by hand): generates the project, builds and tests the app on a simulator. Logs: branch `ci-logs-app`.
  macOS minutes are ten times as expensive as Linux minutes on a private repo, so batch app changes before building.

Read a result without a GitHub login:

```bash
git fetch origin ci-logs-core && git show origin/ci-logs-core:status.txt
git show origin/ci-logs-core:core-test.log       # app: ci-logs-app, app-test.log, generate.log
```
