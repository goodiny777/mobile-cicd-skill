#!/bin/bash
# ci_scripts/ci_post_clone.sh — Xcode Cloud, native iOS (Swift) project.
# Place next to the .xcodeproj/.xcworkspace the workflow points at.
#
# A pure-SPM native project often needs NO ci_scripts at all. Use this one when you want:
#   - a tag ↔ MARKETING_VERSION guard
#   - compile-time config injected from console env vars via an xcconfig
#   - a required-key gate
#   - CocoaPods (pod install) if the project uses it
#   - build notifications
#
# Console env vars: REQUIRED_KEYS, OPTIONAL_KEYS, <the keys themselves>, notification vars.
# KMP: add `brew install openjdk@17` and the Gradle framework step below (see comment).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../common/notify.sh
source "$SCRIPT_DIR/notify.sh"

log() { echo "[post-clone] $*"; }
die() { echo "[post-clone] ERROR: $*" >&2; notify "FAILED" "post-clone: $*"; exit 1; }

cd "$PROJECT_DIR"

# 1. Tag ↔ MARKETING_VERSION guard
PBXPROJ="$(ls -d ./*.xcodeproj | head -1)/project.pbxproj"
MARKETING_VERSION="$(grep -m1 -E 'MARKETING_VERSION = ' "$PBXPROJ" | sed -E 's/.*= *([0-9.]+);.*/\1/')"
if [ -n "${CI_TAG:-}" ] && [ -n "$MARKETING_VERSION" ]; then
  TAG_VERSION="${CI_TAG#ios/v}"
  [ "$TAG_VERSION" = "$MARKETING_VERSION" ] || die "tag ${CI_TAG} → ${TAG_VERSION} ≠ MARKETING_VERSION ${MARKETING_VERSION}"
  log "tag matches MARKETING_VERSION ${MARKETING_VERSION}"
fi

# 2. Required keys gate
for key in ${REQUIRED_KEYS:-}; do
  val="${!key:-}"
  [ -n "$val" ] || die "required env var ${key} unset — add it in App Store Connect → workflow → Environment → Environment Variables"
  log "${key} present (${#val} characters) — value not logged"
done

# 3. Inject config as an xcconfig the project includes (e.g. Config/CI.xcconfig, gitignored,
#    referenced from Release configuration). Info.plist reads $(KEY).
CONFIG_XCCONFIG="${CONFIG_XCCONFIG:-Config/CI.xcconfig}"
mkdir -p "$(dirname "$CONFIG_XCCONFIG")"
: > "$CONFIG_XCCONFIG"
for key in ${REQUIRED_KEYS:-} ${OPTIONAL_KEYS:-}; do
  val="${!key:-}"
  [ -n "$val" ] || continue
  # xcconfig treats // as a comment — escape slashes in URLs
  printf '%s = %s\n' "$key" "${val//\/\//\/$()\/}" >> "$CONFIG_XCCONFIG"
  log "${CONFIG_XCCONFIG} ← ${key}=<redacted, ${#val} chars>"
done

# 4. KMP only: build the shared framework prerequisites
# brew install openjdk@17 && export JAVA_HOME="$(brew --prefix openjdk@17)"
# (cd .. && ./gradlew :shared:podInstall)   # or embedAndSignAppleFrameworkForXcode runs in the Xcode build phase

# 5. CocoaPods, if used
if [ -f Podfile ]; then
  if ! /usr/bin/ruby -e "require 'xcodeproj'" >/dev/null 2>&1; then
    /usr/bin/gem install --user-install --no-document xcodeproj >/dev/null
  fi
  pod install
fi

notify "STARTED" "v${MARKETING_VERSION:-?}"
log "done"
