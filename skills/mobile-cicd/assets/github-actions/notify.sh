#!/bin/bash
# .github/scripts/notify.sh — Telegram and/or Slack notification for GitHub Actions.
# Reads: TEXT, NOTIFY (telegram|slack|both|none), TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, SLACK_WEBHOOK_URL.
# Never fails the job; never prints a token.
set -uo pipefail
TEXT="${TEXT:-build notification}"
MODE="${NOTIFY:-both}"
sent=0
if [ "$MODE" = "telegram" ] || [ "$MODE" = "both" ]; then
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    code=$(curl -sS -o /dev/null -w '%{http_code}' --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${TEXT}" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>/dev/null || echo 000)
    echo "[notify] telegram HTTP ${code}"; sent=1
  else
    echo "[notify] telegram selected but TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID not set — skipped"
  fi
fi
if [ "$MODE" = "slack" ] || [ "$MODE" = "both" ]; then
  if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    payload=$(printf '{"text":"%s"}' "$(printf '%s' "$TEXT" | sed 's/"/\\"/g')")
    code=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL" 2>/dev/null || echo 000)
    echo "[notify] slack HTTP ${code}"; sent=1
  else
    echo "[notify] slack selected but SLACK_WEBHOOK_URL not set — skipped"
  fi
fi
[ "$sent" -eq 0 ] && echo "[notify] nothing sent (NOTIFY=${MODE})"
exit 0
