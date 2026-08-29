#!/bin/bash
# notify.sh — build notifications for Xcode Cloud ci_scripts and GitHub Actions.
# Sourced by the ci_*.sh templates. Silent no-op when nothing is configured.
#
# Supported backends (set the corresponding variables in the CI environment):
#   Telegram: TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#   Slack:    SLACK_WEBHOOK_URL
#
# Usage:  notify "STARTED" "extra text"
#         notify "ARCHIVED" "1.2.0 (42)"
#         notify "FAILED"   "xcodebuild exit 65"
#
# Never echoes the token or webhook. Failures to deliver never fail the build.

notify() {
  local status="$1"
  local detail="${2:-}"
  local app="${APP_DISPLAY_NAME:-iOS}"
  local text="[${app}] ${status}"
  [ -n "$detail" ] && text="${text} — ${detail}"
  [ -n "${CI_TAG:-}" ] && text="${text} | tag ${CI_TAG}"
  [ -n "${CI_BUILD_NUMBER:-}" ] && text="${text} | build ${CI_BUILD_NUMBER}"

  local sent=0
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    local code
    code=$(curl -sS -o /dev/null -w '%{http_code}' \
      --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${text}" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>/dev/null || echo "000")
    echo "[notify] Telegram ${status} notification sent (HTTP ${code})"
    sent=1
  fi
  if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    local payload
    payload=$(printf '{"text":"%s"}' "$(printf '%s' "$text" | sed 's/"/\\"/g')")
    local code
    code=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-type: application/json' \
      --data "$payload" "$SLACK_WEBHOOK_URL" 2>/dev/null || echo "000")
    echo "[notify] Slack ${status} notification sent (HTTP ${code})"
    sent=1
  fi
  [ "$sent" -eq 0 ] && echo "[notify] no notification backend configured — skipping (${status})"
  return 0
}
