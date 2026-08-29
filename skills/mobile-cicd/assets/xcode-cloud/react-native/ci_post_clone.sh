#!/bin/bash
# ios/ci_scripts/ci_post_clone.sh — Xcode Cloud, React Native project.
#
# Console env vars: NODE_MAJOR (e.g. 20), REQUIRED_KEYS, OPTIONAL_KEYS, the keys, notification vars.
# Config injection targets react-native-config's .env at the repo root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
# shellcheck source=../common/notify.sh
source "$SCRIPT_DIR/notify.sh"

log() { echo "[post-clone] $*"; }
die() { echo "[post-clone] ERROR: $*" >&2; notify "FAILED" "post-clone: $*"; exit 1; }

cd "$REPO_ROOT"

# 1. Tag ↔ package.json version guard
PKG_VERSION="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' package.json | head -1)"
if [ -n "${CI_TAG:-}" ]; then
  TAG_VERSION="${CI_TAG#ios/v}"
  [ "$TAG_VERSION" = "$PKG_VERSION" ] || die "tag ${CI_TAG} → ${TAG_VERSION} ≠ package.json version ${PKG_VERSION}"
  log "tag matches package.json version ${PKG_VERSION}"
fi

# 2. Required keys gate
for key in ${REQUIRED_KEYS:-}; do
  val="${!key:-}"
  [ -n "$val" ] || die "required env var ${key} unset — add it in App Store Connect → workflow → Environment → Environment Variables"
  log "${key} present (${#val} characters) — value not logged"
done

# 3. Node
NODE_MAJOR="${NODE_MAJOR:-20}"
if ! command -v node >/dev/null 2>&1 || [ "$(node -v | sed 's/^v\([0-9]*\).*/\1/')" != "$NODE_MAJOR" ]; then
  log "installing node@${NODE_MAJOR} via Homebrew"
  brew install "node@${NODE_MAJOR}" >/dev/null
  brew link --overwrite --force "node@${NODE_MAJOR}" >/dev/null
fi
node -v
export CI=true
if [ -f yarn.lock ]; then corepack enable >/dev/null 2>&1 || true; yarn install --frozen-lockfile; else npm ci; fi

# 4. .env for react-native-config (values never logged)
: > .env
for key in ${REQUIRED_KEYS:-} ${OPTIONAL_KEYS:-}; do
  val="${!key:-}"
  [ -n "$val" ] || continue
  printf '%s=%s\n' "$key" "$val" >> .env
  log ".env ← ${key}=<redacted, ${#val} chars>"
done

# 5. CocoaPods
if ! /usr/bin/ruby -e "require 'xcodeproj'" >/dev/null 2>&1; then
  /usr/bin/gem install --user-install --no-document xcodeproj >/dev/null
fi
(cd ios && pod install)

notify "STARTED" "v${PKG_VERSION}"
log "done"
