#!/bin/bash
# ios/ci_scripts/ci_pre_xcodebuild.sh — Xcode Cloud, React Native.
# Gate: every REQUIRED_KEYS entry must be a non-empty line in the root .env.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
# shellcheck source=../common/notify.sh
source "$SCRIPT_DIR/notify.sh"
die() { echo "[pre-xcodebuild] ERROR: $*" >&2; notify "FAILED" "gate: $*"; exit 1; }

[ -f "$REPO_ROOT/.env" ] || die ".env missing — did ci_post_clone.sh run?"
for key in ${REQUIRED_KEYS:-}; do
  grep -qE "^${key}=." "$REPO_ROOT/.env" || die "${key} empty or absent in .env"
  echo "[pre-xcodebuild] ${key} present in .env — value not logged"
done
echo "[pre-xcodebuild] gate passed"
