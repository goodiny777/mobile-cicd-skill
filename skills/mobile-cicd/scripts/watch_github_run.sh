#!/bin/bash
# watch_github_run.sh — wait for the GitHub Actions run started by a tag/branch push, then
# print a focused failure log if it failed.
#
# Usage: scripts/watch_github_run.sh <workflow-file-or-name> [ref]     e.g. release-android.yml android/v1.2.0
# Requires: gh (authenticated), jq.
# Exit code: 0 on success, 1 on failure/timeout.

set -uo pipefail
WF="${1:?workflow file or name}"
REF="${2:-}"
TIMEOUT="${TIMEOUT:-1800}"

command -v gh >/dev/null || { echo "gh CLI required (https://cli.github.com)"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }

echo "waiting for a run of $WF${REF:+ on $REF}…"
RUN_ID=""
for _ in $(seq 1 30); do
  if [ -n "$REF" ]; then
    RUN_ID="$(gh run list --workflow "$WF" --limit 20 --json databaseId,headBranch,event,createdAt \
      | jq -r --arg ref "${REF#refs/tags/}" '[.[] | select(.headBranch==$ref)] | sort_by(.createdAt) | last | .databaseId // empty')"
  else
    RUN_ID="$(gh run list --workflow "$WF" --limit 1 --json databaseId | jq -r '.[0].databaseId // empty')"
  fi
  [ -n "$RUN_ID" ] && break
  sleep 5
done
[ -n "$RUN_ID" ] || { echo "no run appeared in 150s — is the trigger right? (tag prefix, workflow enabled, tag pushed: git ls-remote --tags origin)"; exit 1; }

echo "run $RUN_ID — $(gh run view "$RUN_ID" --json url -q .url)"
timeout "$TIMEOUT" gh run watch "$RUN_ID" --exit-status >/dev/null 2>&1
STATUS=$?
CONCL="$(gh run view "$RUN_ID" --json conclusion -q .conclusion)"
echo "conclusion: ${CONCL:-running/timeout}"

if [ "$STATUS" -eq 0 ] && [ "$CONCL" = "success" ]; then
  gh run view "$RUN_ID" --json jobs -q '.jobs[] | "\(.name): \(.conclusion) (\((.completedAt|fromdate) - (.startedAt|fromdate)) s)"'
  exit 0
fi

echo
echo "===== failed steps ====="
gh run view "$RUN_ID" --json jobs -q '.jobs[] | select(.conclusion=="failure") | .steps[] | select(.conclusion=="failure") | "\(.name)"'
echo
echo "===== failed log (last 120 lines) ====="
gh run view "$RUN_ID" --log-failed 2>/dev/null | grep -vE '^\s*$' | tail -120
echo
echo "hint: match the message against references/troubleshooting.md; F-4 (toolchain pin), F-8 (stale lock), F-16/17 (Play) are the usual suspects."
exit 1
