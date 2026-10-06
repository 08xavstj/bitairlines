#!/usr/bin/env bash
# Prints the id of the iPhone simulator CI runs on: an iPhone 17 Pro when the runner has one, otherwise the first available
# iPhone, so a new macOS runner image with different simulators does not break the build.
set -euo pipefail
list=$(xcrun simctl list devices available)
id_pattern='[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}'
udid=$(echo "$list" | grep -E "iPhone 17 Pro \(" | head -1 | grep -oE "$id_pattern" || true)
if [ -z "$udid" ]; then
  udid=$(echo "$list" | grep -E "iPhone [0-9]+" | head -1 | grep -oE "$id_pattern" || true)
fi
echo "$udid"
