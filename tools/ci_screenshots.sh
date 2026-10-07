#!/usr/bin/env bash
# Boots an iPhone simulator, launches the Debug app on each demo screen (BitAirlines/App/Demo.swift) and saves a screenshot of each
# to ci-out/shots/<name>.png. CI publishes them to the ci-logs-app branch so the real screens can be looked at without a Mac.
#   tools/ci_screenshots.sh path/to/BitAirlines.app <simulator-udid>
set -u
APP="$1"
UDID="$2"
BUNDLE="ca.amaruq.bitairlines"
OUT="ci-out/shots"
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

for name in title new0 scenarios new1 new2 new3 new4 new5 map airport planner jobs fleet pilots routes bases market money inbox airline issue perks tutorial1 tutorial2 tutorial3; do
  xcrun simctl terminate "$UDID" "$BUNDLE" 2> /dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -SkipSplash -DemoScreen "$name" > /dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" > /dev/null 2>&1
  echo "shot $name: $(ls -l "$OUT/$name.png" 2>/dev/null | awk '{print $5}') bytes"
done
