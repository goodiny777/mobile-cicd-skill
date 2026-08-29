#!/bin/bash
# ios/ci_scripts/ci_post_xcodebuild.sh — Xcode Cloud, any stack.
#
# Reports the ARCHIVE result. Says ARCHIVED, never DEPLOYED: TestFlight delivery
# (Distribution Preparation + post-actions) happens AFTER this script and cannot be
# observed from here. Configure the Email post-action in the console as the backstop.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
# shellcheck source=../common/notify.sh
source "$SCRIPT_DIR/notify.sh"

VERSION=""
if [ -f "$REPO_ROOT/pubspec.yaml" ]; then
  VERSION="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$REPO_ROOT/pubspec.yaml" | head -1)"
fi
[ -n "$VERSION" ] || VERSION="${CI_TAG:-unknown}"

EXIT_CODE="${CI_XCODEBUILD_EXIT_CODE:-unknown}"
ACTION="${CI_XCODEBUILD_ACTION:-archive}"

if [ "$EXIT_CODE" = "0" ]; then
  notify "ARCHIVED" "v${VERSION} (${CI_BUILD_NUMBER:-?}) — ${ACTION} OK; TestFlight delivery follows (not observable here)"
else
  notify "FAILED" "v${VERSION} (${CI_BUILD_NUMBER:-?}) — ${ACTION} exit ${EXIT_CODE}"
fi
echo "[post-xcodebuild] done (xcodebuild exit ${EXIT_CODE})"
