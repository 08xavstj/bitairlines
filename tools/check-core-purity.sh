#!/usr/bin/env bash
# Enforces the rule "game logic stays UI-free, platform-free and deterministic".
#
# Scans the AirlineCore Swift package sources for imports and APIs that must never appear in game logic:
# UI/persistence frameworks, system randomness, wall-clock time, locale/formatting, console output, and
# libm functions whose results can differ across platforms (iOS vs Android).
# Comments are ignored (a doc comment may mention a forbidden API); string literals are not parsed.
#
# Usage:  check-core-purity.sh [path-to-AirlineCore/Sources]   (default: ./AirlineCore/Sources)
# Exit:   0 clean, 1 violations found, 2 directory not found, 3 internal error.
# Opt-out for a single line (must be justified in a comment on the same line):  // purity:allow <reason>
set -u

DIR="${1:-AirlineCore/Sources}"
if [ ! -d "$DIR" ]; then
  echo "check-core-purity: directory not found: $DIR" >&2
  echo "Pass the AirlineCore Sources path, or run from the repo root once the package exists." >&2
  exit 2
fi

# Emit "path:line: code" for every Swift source line, with comments removed and purity:allow lines skipped.
code_stream() {
  find "$DIR" -name '*.swift' -print0 | sort -z | xargs -0 awk '
    FNR == 1 { inblock = 0 }
    {
      line = $0
      if (line ~ /purity:allow/) next
      out = ""
      while (length(line) > 0) {
        if (inblock) {
          end = index(line, "*/")
          if (end == 0) { line = ""; break }
          line = substr(line, end + 2); inblock = 0; continue
        }
        sl = index(line, "//"); bl = index(line, "/*")
        if (sl > 0 && (bl == 0 || sl < bl)) { out = out substr(line, 1, sl - 1); line = ""; break }
        if (bl > 0) { out = out substr(line, 1, bl - 1); line = substr(line, bl + 2); inblock = 1; continue }
        out = out line; line = ""
      }
      if (out ~ /[^[:space:]]/) printf "%s:%d: %s\n", FILENAME, FNR, out
    }'
}

STREAM="$(code_stream)"
fail=0

scan() {            # scan <label> <extended-regex> [exclude-regex: matching lines are allowed]
  local label="$1" pattern="$2" exclude="${3:-}" hits
  hits=$(printf '%s\n' "$STREAM" | grep -E ":[0-9]+:.*($pattern)")
  if [ $? -eq 2 ]; then echo "check-core-purity: internal error (bad regex) in rule: $label" >&2; exit 3; fi
  if [ -n "$exclude" ] && [ -n "$hits" ]; then hits=$(printf '%s\n' "$hits" | grep -vE "$exclude" || true); fi
  if [ -n "$hits" ]; then
    echo "VIOLATION: $label"
    echo "$hits" | sed 's/^/    /'
    echo
    fail=1
  fi
}

# --- forbidden imports -----------------------------------------------------------------------------
scan "UI / platform / persistence framework import (Core must be portable and UI-free)" \
     '[[:space:]](@preconcurrency[[:space:]]+)?import[[:space:]]+(SwiftUI|SwiftData|UIKit|AppKit|Combine|Observation|CoreData|CloudKit|StoreKit|GameKit|GameplayKit|SpriteKit|SceneKit|RealityKit|AVFoundation|OSLog|os|Metal|CoreGraphics|CoreLocation|UserNotifications|WidgetKit|AppIntents)\b'

# --- nondeterminism: randomness, time, identity ----------------------------------------------------
# A call that passes an explicit generator (`using:`) is deterministic, so it is allowed.
scan "System randomness (use the injected SeededRandom)" \
     'SystemRandomNumberGenerator|\.random\(|arc4random|drand48|\brandom\(\)|\.shuffled\(|\.randomElement\(' \
     'using:'
scan "Wall-clock time (use the GameDate week counter)" \
     '\bDate\(\)|Date\.now|\bCFAbsoluteTimeGetCurrent|ContinuousClock\(\)|SuspendingClock\(\)|DispatchTime\.now|\btime\(nil\)'
scan "Random identity (UUID()); IDs are deterministic counters allocated by world state" \
     '\bUUID\(\)'

# --- platform-dependent behaviour ------------------------------------------------------------------
scan "libm functions differ in the last bit across platforms; use arithmetic, tables, or sqrt" \
     '[^A-Za-z0-9_.](pow|exp|exp2|log|log2|log10|sin|cos|tan|atan|atan2|tanh|cbrt)\('
scan "Locale / formatting in game logic (formatting belongs to the app layer)" \
     '\bLocale\b|String\(format:|NumberFormatter|DateFormatter|\.formatted\(|ByteCountFormatter'
scan "Environment / filesystem / defaults access (belongs to the app layer)" \
     '\bUserDefaults\b|\bProcessInfo\b|\bFileManager\b|\bBundle\.(main|module)\b|NSHomeDirectory|\bURLSession\b'
scan "Threads / main-queue use in game logic (Core is synchronous and pure; concurrency lives in the app layer)" \
     '\bDispatchQueue\b|\bThread\.|\bOperationQueue\b|@MainActor|MainActor\.run'

# --- hygiene ---------------------------------------------------------------------------------------
scan "Console output in Core (return data; the app layer logs)" \
     '[^A-Za-z0-9_.](print|debugPrint|dump|NSLog)\(|\bLogger\(|\bos_log\('
scan "Force-try / fatalError in game logic (return a typed error or a safe default)" \
     '\btry!|fatalError\(|preconditionFailure\('

# --- player-facing strings -------------------------------------------------------------------------
scan "Player-visible text in Core (emit events; the app layer localizes)" \
     'LocalizedStringKey|NSLocalizedString|String\(localized:'

if [ "$fail" -eq 0 ]; then
  echo "check-core-purity: OK ($DIR is clean)"
  exit 0
fi
echo "check-core-purity: FAILED. Fix the violations above or, if truly justified, annotate the line with '// purity:allow <reason>'."
exit 1
