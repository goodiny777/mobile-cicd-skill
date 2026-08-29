# Changelog

## 1.0.1 — 2026-08-29

- Cross-platform: new `references/platform-notes.md` (Windows PowerShell / Git Bash, macOS, Linux differences; which tasks need a Mac and the workarounds).
- New `scripts/fix_exec_bits.sh` and `scripts/fix_exec_bits.ps1` — set `100755` in the git index without relying on shell glob expansion (PowerShell silently ignores `git update-index --chmod=+x dir/*.sh`).
- Harness error message now points at the fix scripts; keystore base64 instructions given per OS.
- Notifications: Telegram or Slack asked up front; Android workflows gained `NOTIFY` and a shared `.github/scripts/notify.sh`.

## 1.0.0 — 2026-08-29

- Initial release: detect → interview → secrets map → generate → console → push/watch/fix loop → runbook.
- Templates: Xcode Cloud `ci_scripts` for Flutter, native iOS, React Native; GitHub Actions Android workflows (Flutter, Gradle) with Google Play, Firebase App Distribution, tag/branch/manual triggers, Telegram/Slack notifications.
- Scripts: `detect_project.sh`, `check_ci_scripts.sh`, `watch_github_run.sh`.
- References: universal runbook, Xcode Cloud console table, Chrome console flow, Play + Firebase setup, failure catalogue (F-1…F-20).
