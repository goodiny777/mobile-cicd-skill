#!/bin/bash
# ci_scripts/ci_pre_xcodebuild.sh — Xcode Cloud, native iOS.
# Gate: every REQUIRED_KEYS entry must have a non-empty line in the CI xcconfig.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../common/notify.sh
source "$SCRIPT_DIR/notify.sh"
die() { echo "[pre-xcodebuild] ERROR: $*" >&2; notify "FAILED" "gate: $*"; exit 1; }

CONFIG_XCCONFIG="$PROJECT_DIR/${CONFIG_XCCONFIG:-Config/CI.xcconfig}"
[ -f "$CONFIG_XCCONFIG" ] || die "${CONFIG_XCCONFIG} missing — did ci_post_clone.sh run?"
for key in ${REQUIRED_KEYS:-}; do
  line="$(grep -E "^${key} = ." "$CONFIG_XCCONFIG" || true)"
  [ -n "$line" ] || die "${key} empty or absent in $(basename "$CONFIG_XCCONFIG")"
  echo "[pre-xcodebuild] ${key} present in xcconfig — value not logged"
done
echo "[pre-xcodebuild] gate passed"
