#!/bin/bash
# ios/ci_scripts/ci_post_clone.sh — Xcode Cloud, Flutter project.
#
# Runs once, right after Apple clones the repo, before any xcodebuild.
# Everything that can fail cheaply fails HERE, before a compute minute is spent.
#
# Environment variables (set in App Store Connect → workflow → Environment → Environment Variables):
#   FLUTTER_VERSION        (not secret)  e.g. 3.47.1 — keep equal to .github/workflows env
#   REQUIRED_KEYS          (not secret)  space-separated names that MUST be non-empty, e.g. "ANALYTICS_API_KEY"
#   <each key in REQUIRED_KEYS>  (secret, "Keep value redacted")
#   OPTIONAL_KEYS          (not secret)  space-separated names written to .env if present, e.g. "PREMIUM_UNLOCKED FLAG_ADS_ENABLED"
#   TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID or SLACK_WEBHOOK_URL (secret, optional)
#   APP_DISPLAY_NAME       (not secret, optional) label used in notifications
#
# Apple-provided: CI_TAG, CI_BUILD_NUMBER, CI_PRIMARY_REPOSITORY_PATH
#
# Constraints (checked by scripts/check_ci_scripts.sh before you push):
#   - this file must be 100755 in the git INDEX and LF-terminated
#   - never echo a secret value; log presence and length only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
# shellcheck source=../common/notify.sh
source "$SCRIPT_DIR/notify.sh"

log() { echo "[post-clone] $*"; }
die() { echo "[post-clone] ERROR: $*" >&2; notify "FAILED" "post-clone: $*"; exit 1; }

cd "$REPO_ROOT"
log "repo root: $REPO_ROOT"

# ---------------------------------------------------------------------------
# 1. Tag ↔ pubspec version guard (cheapest check, first)
# ---------------------------------------------------------------------------
PUBSPEC_VERSION="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' pubspec.yaml | head -1)"
[ -n "$PUBSPEC_VERSION" ] || die "could not read version: from pubspec.yaml"
if [ -n "${CI_TAG:-}" ]; then
  TAG_VERSION="${CI_TAG#ios/v}"
  [ "$TAG_VERSION" = "$PUBSPEC_VERSION" ] || \
    die "tag ${CI_TAG} → ${TAG_VERSION} does not match pubspec.yaml version ${PUBSPEC_VERSION}; bump pubspec or retag"
  log "tag ${CI_TAG} matches pubspec version ${PUBSPEC_VERSION}"
else
  log "no CI_TAG (manual start) — skipping tag/version guard, building ${PUBSPEC_VERSION}"
fi

# ---------------------------------------------------------------------------
# 2. Required keys gate — fail before any download
# ---------------------------------------------------------------------------
for key in ${REQUIRED_KEYS:-}; do
  val="${!key:-}"
  [ -n "$val" ] || die "required environment variable ${key} is unset or empty. Add it in App Store Connect → workflow → Environment → Environment Variables (tick 'Keep value redacted')."
  log "${key} present (${#val} characters) — value not logged"
done

# ---------------------------------------------------------------------------
# 3. Flutter SDK
# ---------------------------------------------------------------------------
FLUTTER_VERSION="${FLUTTER_VERSION:?set FLUTTER_VERSION in the workflow environment}"
FLUTTER_HOME="$HOME/flutter"
if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  log "cloning Flutter ${FLUTTER_VERSION}"
  git clone --quiet --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"
flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache --ios

# ---------------------------------------------------------------------------
# 4. Ruby gem that some plugin podspecs need under system Ruby (see troubleshooting F-7)
# ---------------------------------------------------------------------------
if ! /usr/bin/ruby -e "require 'xcodeproj'" >/dev/null 2>&1; then
  log "installing xcodeproj gem for system Ruby (podspec helpers require it)"
  /usr/bin/gem install --user-install --no-document xcodeproj >/dev/null
fi

# ---------------------------------------------------------------------------
# 5. Dart deps
# ---------------------------------------------------------------------------
flutter pub get

# ---------------------------------------------------------------------------
# 6. .env for --dart-define-from-file (values never logged)
# ---------------------------------------------------------------------------
ENV_FILE="$REPO_ROOT/.env"
: > "$ENV_FILE"
for key in ${REQUIRED_KEYS:-} ${OPTIONAL_KEYS:-}; do
  val="${!key:-}"
  if [ -n "$val" ]; then
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
    log ".env ← ${key}=<redacted, ${#val} chars>"
  else
    log ".env: optional ${key} not set — skipped"
  fi
done

# ---------------------------------------------------------------------------
# 7. Stale Podfile.lock handling — REMOVE this block once the lock is regenerated on a Mac
#    and committed. Deleting it here un-pins pods in CI (reproducibility loss; see runbook §7).
# ---------------------------------------------------------------------------
if [ "${DELETE_STALE_PODFILE_LOCK:-false}" = "true" ] && [ -f ios/Podfile.lock ]; then
  log "DELETE_STALE_PODFILE_LOCK=true → removing ios/Podfile.lock (pods un-pinned for this build)"
  rm -f ios/Podfile.lock
fi

# ---------------------------------------------------------------------------
# 8. Config-only build: generates ios/Flutter/Generated.xcconfig AND runs pod install.
#    Do NOT run `pod install` again after this (troubleshooting F-9).
# ---------------------------------------------------------------------------
flutter build ios --config-only --release --no-codesign --dart-define-from-file="$ENV_FILE"

[ -f ios/Flutter/Generated.xcconfig ] || die "Generated.xcconfig missing after config-only build"
[ -d ios/Pods ] || log "warning: ios/Pods not present — project may be on SPM (needs committed Package.resolved)"

notify "STARTED" "v${PUBSPEC_VERSION}"
log "done"
