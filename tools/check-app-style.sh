#!/usr/bin/env bash
# Enforces the app's pixel UI and voice rules (see .claude/skills/bitairlines-swift/SKILL.md, "App rules", and CLAUDE.md):
# no RoundedRectangle or Capsule (panels are PixelShape), no SF Symbols (icons are PixelIcon), no system alerts or
# confirmation dialogs (use pixelConfirm), no gradients, ASCII only (the pixel font has no accents or em dashes), and no
# exclamation marks in player-facing text.
#
# Usage:  check-app-style.sh [path-to-app-sources]   (default: ./BitAirlines)
# Exit:   0 clean, 1 violations found, 2 directory not found.
# Opt-out for a single line (say why in the same comment):  // style:allow <reason>
# Comments starting with // after a space or at the start of a line are ignored, so "https://" in a string is kept.
set -u

DIR="${1:-BitAirlines}"
if [ ! -d "$DIR" ]; then
  echo "check-app-style: directory not found: $DIR" >&2
  exit 2
fi

# "path:line: code" for every Swift line, with // comments removed and style:allow lines skipped.
STREAM="$(find "$DIR" -name '*.swift' -print0 | sort -z | xargs -0 awk '
  {
    line = $0
    if (line ~ /style:allow/) next
    sub(/(^|[[:space:]])\/\/.*$/, "", line)
    if (line ~ /[^[:space:]]/) printf "%s:%d: %s\n", FILENAME, FNR, line
  }')"
fail=0

report() {          # report <label> <hits>
  if [ -n "$2" ]; then
    echo "VIOLATION: $1"
    echo "$2" | sed 's/^/    /'
    echo
    fail=1
  fi
}

report "RoundedRectangle or Capsule (use PixelShape or PixelPanel)" \
  "$(printf '%s\n' "$STREAM" | grep -E ':[0-9]+:.*(RoundedRectangle|Capsule\()' || true)"
report "SF Symbols (use a 12 x 12 PixelIcon)" \
  "$(printf '%s\n' "$STREAM" | grep -E ':[0-9]+:.*(Image\(systemName:|systemImage:|Label\([^)]*systemImage)' || true)"
report "System alert or confirmation dialog (use pixelConfirm or a game dialog)" \
  "$(printf '%s\n' "$STREAM" | grep -E ':[0-9]+:.*(\.alert\(|\.confirmationDialog\(|UIAlertController)' || true)"
report "Gradient (flat colours only)" \
  "$(printf '%s\n' "$STREAM" | grep -E ':[0-9]+:.*Gradient' || true)"
report "Non-ASCII character (the pixel font is ASCII only; write - or a comma, not an em dash)" \
  "$(printf '%s\n' "$STREAM" | LC_ALL=C grep -n '[^[:print:][:space:]]' | sed 's/^[0-9]*://' || true)"
report "Exclamation mark in a string (plain voice, no exclamation marks)" \
  "$(printf '%s\n' "$STREAM" | grep -E '"([^"\\]|\\.)*![^="]([^"\\]|\\.)*"|"([^"\\]|\\.)*!"' | grep -vE '\\\(!' || true)"

if [ "$fail" -eq 0 ]; then
  echo "check-app-style: OK ($DIR is clean)"
  exit 0
fi
echo "check-app-style: FAILED. Fix the lines above or, if truly needed, add '// style:allow <reason>' to the line."
exit 1
