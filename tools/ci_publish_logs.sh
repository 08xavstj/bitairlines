#!/usr/bin/env bash
# Publishes trimmed CI logs to a branch (CI_LOG_BRANCH, default ci-logs; force-pushed each run) so compiler and test output can be read
# with a plain `git fetch origin <branch>` and no GitHub login. Arguments are "name=outcome" pairs written to status.txt.
set -u

SHA="${GITHUB_SHA:-local}"
BRANCH="${CI_LOG_BRANCH:-ci-logs}"
TMP="$(mktemp -d)"

{
  echo "commit: $SHA"
  echo "run: ${GITHUB_RUN_ID:-none}"
  echo "time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for kv in "$@"; do echo "$kv"; done
} > "$TMP/status.txt"

for f in ci-out/*.log; do
  [ -f "$f" ] || continue
  {
    echo "### matches"
    grep -E "error:|warning: var|warning: imm|Fatal error|Issue recorded|Expectation failed|failed|FAILED|VIOLATION" "$f" | head -150
    echo
    echo "### last 80 lines"
    tail -n 80 "$f"
  } > "$TMP/$(basename "$f")"
done

git config user.name "ci-logs"
git config user.email "ci-logs@users.noreply.github.com"
git checkout --orphan ci-logs-publish
git rm -rf --quiet .
git clean -fdxq
cp "$TMP"/* .
git add -A
git commit --quiet -m "CI logs for $SHA"
git push --force origin "HEAD:$BRANCH"
