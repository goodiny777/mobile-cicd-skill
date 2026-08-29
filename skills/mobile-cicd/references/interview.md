# Interview — question bank and the answers' consequences

Ask one topic at a time. Skip what `detect_project.sh` already answered. Write each answer into the runbook §10 draft as you go. Use AskUserQuestion when available; keep options to 2–4.

## Q1. Platforms (only when both modules exist)

"The repo has both an Android module (`<dir>`) and an iOS project (`<dir>`). Which should get a release pipeline now — Android, iOS, or both?"

Consequence: only the chosen platform's files are generated; the runbook notes the other as "not configured, <date>".

## Q2. Deploy targets

**Android** — "Where should Android builds go?"
- Google Play — which track? `internal` (default; instant, ≤100 testers), `alpha`/`beta` (closed/open testing), `production`. Production: recommend a GitHub Environment with required reviewers.
- Firebase App Distribution — which tester groups (comma-separated aliases)? Needs a Firebase project with the Android app registered and a service account with *Firebase App Distribution Admin*.
- Both — Play first, Firebase as a second step; each has its own service account.

**iOS** — "Where should iOS builds go?"
- TestFlight internal (default) → Xcode Cloud *Distribution Preparation: TestFlight (Internal Testing Only)*, Clean **off**.
- TestFlight external → Apple requires Clean **on**; note the compute cost in §8.
- App Store submission → *TestFlight and App Store*; submission itself stays manual unless they explicitly want auto-submit.
- Firebase App Distribution → needs an ad-hoc-signed IPA; Xcode Cloud exposes it as `CI_AD_HOC_SIGNED_APP_PATH` in `ci_post_xcodebuild.sh`. Registered device UDIDs must be in the ad-hoc profile (managed signing handles the profile; devices must be in the team). See `firebase-app-distribution.md`.

## Q3. Trigger rule

"What should start a release build?"

| Choice | GitHub Actions `on:` | Xcode Cloud start condition | Say this |
|---|---|---|---|
| **Tag prefix** (recommended) | `push: tags: ['android/v*']` | Tag Changes → "Tags beginning with `ios/v`" | Deliberate, per-platform, free when idle; bare `v*` is a no-op |
| Branch | `push: branches: [release]` (never `main` unless they insist) | Branch Changes → `release` | Every push bills a full build; doc-only commits too. Suggest `paths-ignore: ['docs/**','*.md']` |
| Manual | `workflow_dispatch:` with `inputs.version` | Manual Start only (no automatic condition) | Someone must click; fine for low cadence |
| All three, prepared | tag + `workflow_dispatch`, branch block commented | Tag condition + Manual Start; branch documented but not added | Let them switch later without you |

Blocks to paste:

```yaml
# tag
on:
  push:
    tags: ['android/v*']

# branch
on:
  push:
    branches: [release]
    paths-ignore: ['docs/**', '**/*.md']

# manual
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to release (must match the project version)'
        required: true
```

The tag↔version guard must read the version from `GITHUB_REF_NAME` for tags, from `inputs.version` for manual, and skip for branch builds (log the project version instead).

## Q4. Secrets — inventory and storage

Ask about existence and ownership, never values.

- "Is there an upload keystore already? Where is it, and who has the password?" If none: give `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`, tell them to keep it outside the repo and back it up, then encode it for the GitHub secret with the one-liner for their OS in `platform-notes.md` §4 (`base64 -w0` is Linux/Git Bash only; macOS needs `base64 -i … | tr -d '\n'`; PowerShell uses `[Convert]::ToBase64String`).
- "Is Play App Signing enabled?" (Play Console → Setup → App signing). If yes, the keystore is only the upload key — losing it is recoverable via Play support.
- "Do you have a Play service account? A Firebase service account?" If not, point at the steps in the respective reference.
- "Which app config keys must be baked into the build?" (analytics, ads, API base URL). Each becomes a `REQUIRED_KEYS` or `OPTIONAL_KEYS` entry; the same key needed by both platforms means **two copies**, note it.
- "Where should GitHub secrets live?"
  - Repository secrets — default.
  - Environment secrets (`production`) with required reviewers — for the production track; the job gets `environment: production`.
  - Organisation secrets — when several repos share the keystore or service account.
- "Where should build notifications go?" Offer, in this order: **Telegram** (needs `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`; the chat id comes from `https://api.telegram.org/bot<token>/getUpdates` after the bot is added to the chat), **Slack** (needs `SLACK_WEBHOOK_URL` from an Incoming Webhook app), both, Xcode Cloud email post-action only, or none. Consequence: `NOTIFY: telegram|slack|both|none` in the Android workflow env; the same secret names entered in GitHub and in the Xcode Cloud environment (redacted). Messages are `STARTED` → `ARCHIVED`/`DEPLOYED`/`FAILED`; iOS says `ARCHIVED` because TestFlight delivery happens after the script.

Consequence: the secrets map (runbook §3) is filled with names and locations; the workflow gets `environment:` if chosen; `REQUIRED_KEYS` is set in both the workflow env and the Xcode Cloud env.

## Q5. Version source of truth and versionCode

- Flutter: `pubspec.yaml` `version: X.Y.Z+N` — tell them `+N` is now ignored by CI.
- Native iOS: `MARKETING_VERSION` in the pbxproj (or an xcconfig).
- RN: `package.json` `version`.
- Gradle: `versionName` in `gradle.properties` or `build.gradle(.kts)`; if it's hard-coded in Gradle, propose the `-PversionName` wiring from the template header.
- "What's the highest `versionCode` Play has ever seen for this package?" → `VERSION_CODE_OFFSET` = that + 1 − current `GITHUB_RUN_NUMBER` (or simply a round number above it).

## Q6. Existing CI to retire

If Phase 0 found a macOS job: "This job costs 10× per minute. After the first green Xcode Cloud build, do you want me to remove it, or leave it disabled as rollback?" Record the six Apple secret names as rollback material either way.

## Confirming the plan

Before generating, restate in ≤5 lines: platforms · targets · trigger · where secrets live · version source. Wait for a yes.
