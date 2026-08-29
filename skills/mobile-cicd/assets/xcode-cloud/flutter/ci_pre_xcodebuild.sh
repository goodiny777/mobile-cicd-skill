#!/bin/bash
# ios/ci_scripts/ci_pre_xcodebuild.sh — Xcode Cloud, Flutter project.
#
# The gate: prove that every REQUIRED_KEYS entry actually reached the build inputs.
# Apple does not wipe Generated.xcconfig between post-clone and archive (verified live),
# but this costs one second and converts a silent runtime failure into a red build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
# shellcheck source=../common/notify.sh
source "$SCRIPT_DIR/notify.sh"

log() { echo "[pre-xcodebuild] $*"; }
die() { echo "[pre-xcodebuild] ERROR: $*" >&2; notify "FAILED" "pre-xcodebuild gate: $*"; exit 1; }

XCCONFIG="$REPO_ROOT/ios/Flutter/Generated.xcconfig"
[ -f "$XCCONFIG" ] || die "Generated.xcconfig not found — did ci_post_clone.sh run?"

# DART_DEFINES is a comma-separated list of base64(KEY=VALUE)
DART_DEFINES_LINE="$(grep -E '^DART_DEFINES=' "$XCCONFIG" || true)"
[ -n "$DART_DEFINES_LINE" ] || die "DART_DEFINES missing from Generated.xcconfig"
DART_DEFINES="${DART_DEFINES_LINE#DART_DEFINES=}"

for key in ${REQUIRED_KEYS:-}; do
  found=""
  IFS=',' read -ra ITEMS <<< "$DART_DEFINES"
  for item in "${ITEMS[@]}"; do
    decoded="$(printf '%s' "$item" | base64 --decode 2>/dev/null || true)"
    case "$decoded" in
      "${key}="*) found="${decoded#"${key}"=}";;
    esac
  done
  [ -n "$found" ] || die "${key} is empty or absent in DART_DEFINES at archive time"
  log "${key} reached DART_DEFINES (${#found} characters) — value not logged"
done

log "gate passed"
