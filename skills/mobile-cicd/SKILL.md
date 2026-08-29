---
name: mobile-cicd
description: Set up, migrate, or debug mobile release CI/CD end to end — detect the project (native iOS/Android, Flutter, React Native, KMP, which modules), interview the owner on what to deploy where (TestFlight/App Store via Xcode Cloud with ci_scripts and managed signing; Google Play and/or Firebase App Distribution via GitHub Actions), where secrets live, and what triggers a release (tag, branch, manual); then generate pipelines, commit, push, watch the first build, read failing logs, fix, and repeat until green. Use whenever the user mentions Xcode Cloud, TestFlight, ci_post_clone.sh, App Store or Play Store deployment, Firebase App Distribution, release tags, macOS runner costs, fastlane replacement, "our iOS build is expensive/slow/flaky", or asks to configure a mobile release workflow — even a bare "set up CI for my app". Also drives the App Store Connect console via Claude in Chrome and writes the project's release runbook.
license: MIT
metadata:
  version: "1.0.0"
  author: goodiny777
  homepage: https://github.com/goodiny777/mobile-cicd-skill
---

# Mobile CI/CD — Xcode Cloud (iOS) + GitHub Actions (Android)

You take a mobile repo from "no release pipeline" (or "expensive hand-rolled one") to a green first build on every platform the owner wants, and leave behind a runbook. The cheapest reliable shape is **Xcode Cloud** for iOS (25 free compute-hours/month with the Apple Developer Program, managed signing, no `.p12`/profile secrets) and a **Linux GitHub Actions** job for Android (1× minute multiplier vs macOS's 10×). Each platform is released by its own trigger; the default is a tag prefix (`ios/v*`, `android/v*`) with a bare `v*` tag as a deliberate no-op.

The reference implementation behind this skill measured **6 billed minutes per iOS release** (down from ~45 GitHub-billed macOS minutes) and hit seven distinct failures on its first live run — every one a pre-existing project defect. `references/troubleshooting.md` lists them so you recognise each in seconds.

This is an interactive, iterative job. You will ask questions, wait for the owner to enter secrets in consoles, push, watch, read logs, fix, push again. Keep a running checklist for the user (the task list) so they can see where you are.

## Phase 0 — Detect (always first, before any question)

Run `scripts/detect_project.sh <repo-root>` and read every line. It reports: stack (`native-ios`, `native-android`, `flutter`, `react-native`, `kmp`, or `multi` when a repo holds separate iOS and Android modules), git submodules, where the Xcode project lives, shared schemes and their Archive config, signing style, CocoaPods/SPM state and `Podfile.lock` age, existing `ci_scripts/`, every GitHub workflow and whether any uses a macOS runner, and for Android: module dirs, `applicationId`, flavors, `signingConfigs` and where they read credentials from, `versionCode`/`versionName` sources, and whether a keystore or `key.properties` is tracked in git.

Don't guess what the script can tell you. Most wrong advice here comes from assuming Flutter when it's RN, or CocoaPods when the project moved to SPM, or a single module when there are three.

If the repo has **both** an iOS and an Android module (any stack), that's the first question of the interview: which to deploy — Android, iOS, or both. Don't set up a platform nobody asked for.

## Phase 1 — Interview

Ask in this order, one topic at a time, and record answers as you go (they become runbook §10). Full question bank with follow-ups: `references/interview.md`. Skip anything Phase 0 already answered.

1. **Platforms** — Android, iOS, both (only if both modules exist).
2. **Deploy targets per platform** — Android: Google Play (which track: internal / closed / open / production), Firebase App Distribution (tester groups), or both. iOS: TestFlight internal, TestFlight external (implies Clean = on), App Store submission, Firebase App Distribution (ad-hoc IPA from Xcode Cloud).
3. **Trigger rule** — tag prefix (recommended, explain why), branch push (which branch; warn that every push bills a build), manual only (`workflow_dispatch` / Xcode Cloud manual start), or "prepare all three and I'll pick".
4. **Secrets: what exists and where it will live** — keystore (exists? where? who has the password?), Play service account, Firebase service account, app config keys (analytics etc.), notification tokens. Offer the storage choices: GitHub repository secrets (default), GitHub Environment secrets with required reviewers (for production), organisation secrets (shared across repos). For iOS: Xcode Cloud environment variables with *Keep value redacted*. Never ask for a value. If the user pastes one anyway, tell them to rotate it and continue with the name only.
5. **Notifications** — ask once, with the two popular options first: **Telegram** (bot token + chat id) or **Slack** (incoming webhook URL); also both, Xcode Cloud email post-action only, or none. The answer sets `NOTIFY` in the Android workflow and which secret names go into both consoles; the scripts already speak both backends, so no code changes are needed.
6. **Version source of truth** — `pubspec.yaml`, `MARKETING_VERSION`, `package.json`, `gradle.properties`; and the `versionCode` offset (ask for the highest versionCode Play has seen, or read it from the Play Console with the user).

Confirm the plan in five lines before generating anything.

## Phase 2 — Secrets setup (user enters values; you verify presence)

Produce the **secrets map**: name → where it lives → every other copy → required (build fails if unset) or optional (warn and continue). Template: `references/runbook.md` §3.

Then guide the owner through entering them, with the exact console paths (`references/runbook.md` §3, `references/github-actions-play.md`, `references/firebase-app-distribution.md`). For the keystore: if none exists, give the `keytool` command and the `base64 -w0` line; the user runs both locally and pastes nothing into chat. For GitHub, verify with `gh secret list` (names only) that every required secret exists before you push. For Xcode Cloud, verify by reading the Environment tab (Chrome, Phase 4) or by asking the user to confirm the names render with asterisks.

Secure extraction in the pipelines is already encoded in the templates: secrets enter through `${{ secrets.X }}` into step-scoped `env`, never interpolated into `run:` strings; the keystore is decoded to a file that is scrubbed in an `if: always()` step; scripts log `KEY present (N chars) — value not logged`; a missing required key fails in the first seconds, before any billed minute.

When migrating from a hand-rolled iOS job, list the old Apple signing secrets by name and tell the user **not to delete them until the first Xcode Cloud release is green** — they are the rollback (`references/runbook.md` §9).

## Phase 3 — Generate

Copy from `assets/` and adapt to the interview answers; the templates are complete and commented, so edit rather than write from scratch.

| Stack | iOS scripts → `ci_scripts/` | Android workflow |
|---|---|---|
| Flutter | `assets/xcode-cloud/flutter/` → `ios/ci_scripts/` | `assets/github-actions/release-android-flutter.yml` |
| Native iOS | `assets/xcode-cloud/native/` → next to the `.xcodeproj` | — |
| Native Android / RN / KMP | RN: `assets/xcode-cloud/react-native/`; KMP: start from native | `assets/github-actions/release-android-gradle.yml` |

Always copy `assets/xcode-cloud/common/notify.sh` beside the iOS scripts, `assets/github-actions/notify.sh` to `.github/scripts/notify.sh`, and append `assets/gitattributes-snippet` to `.gitattributes`.

Adapt to the answers: set `on:` per the trigger rule (`references/interview.md` has the three `on:` blocks); enable the Firebase step and/or the Play step; set `PACKAGE_NAME`, `VERSION_CODE_OFFSET`, `REQUIRED_KEYS`, flavor/task names from what Phase 0 read out of Gradle; for iOS set `REQUIRED_KEYS` in the console and, if Firebase, the `firebase appdistribution` block in `ci_post_xcodebuild.sh`.

Rules the templates encode — keep them:

- **Fail fast, before compute is spent** — tag↔version guard and required-key gate in the first seconds.
- **Gate the injected config** — `ci_pre_xcodebuild.sh` proves keys reached `Generated.xcconfig`/xcconfig/`.env`.
- **Log presence, not values.**
- **`ARCHIVED`, not `DEPLOYED`** from `ci_post_xcodebuild.sh` — TestFlight delivery happens after it; the email post-action is the backstop.
- **No double `pod install`** in Flutter.
- **`100755` in the git index and LF endings** — `git update-index --chmod=+x <dir>/ci_scripts/*.sh`. This is the most common reason Apple silently ignores the scripts, and it's invisible on disk on Windows.

Then run `scripts/check_ci_scripts.sh <repo-root>` and fix every FAIL before Phase 5.

## Phase 4 — Console configuration (iOS)

The Xcode Cloud workflow lives in App Store Connect, not git. First-time creation must happen once from Xcode on a Mac (tell the user exactly: Xcode → Product → Xcode Cloud → Create Workflow, pick the shared scheme, accept defaults — you'll fix them next). After that everything is web-editable.

If Claude in Chrome tools are available (or can be loaded with ToolSearch), **ask the user for permission to drive App Store Connect in their Chrome**, then follow `references/console-chrome-flow.md` against the setting table in `references/xcode-cloud-console.md`. Hard limits: never type a secret value into a form (fill the name, tick *Keep value redacted*, hand over to the user for the value); never delete anything except the default *Branch Changes → main* start condition, and only after the tag condition exists; read the page before and after each change. If Chrome isn't available, walk the user through the same table verbally and have them read back what the page shows.

For Android the console work is the Play service account + first manual AAB upload, and/or the Firebase project + App Distribution groups — `references/github-actions-play.md`, `references/firebase-app-distribution.md`.

## Phase 5 — Commit, push, watch, fix, repeat

1. Commit on a branch (`ci/mobile-release-pipeline`), push, open a PR unless the user wants direct-to-main. Commit message states the tag scheme and that the iOS pipeline is outside `.github/`.
2. Merge (with the user), then fire the trigger: push `android/vX.Y.Z` and/or `ios/vX.Y.Z` for a version that matches the project, or `gh workflow run` / Xcode Cloud manual start if that's the rule.
3. **Android:** `scripts/watch_github_run.sh` wraps `gh run watch` and, on failure, prints `gh run view --log-failed` trimmed to the failing step. Read it, match against `references/troubleshooting.md`, fix, commit, retag (`vX.Y.Z-rc2` style is fine for iteration if the version guard allows it — or bump the offset only), push, watch again.
4. **iOS:** Xcode Cloud logs are in App Store Connect → Xcode Cloud → Builds → the build → the failed action's log. Read them through Chrome (`get_page_text` on the log pane) or ask the user to paste the last ~80 lines of the failed step. `ci_post_clone.sh` failures are yours to fix in the script; Apple-step failures usually trace back to the console table or to signing.
5. Expect **3–8 fix commits** on a first live run and say so up front, so nobody panics at failure #3. Stop and ask only when a fix needs something you can't do: a Mac (regenerating `Podfile.lock`, committing `Package.resolved`), a console value, or a Play/Firebase permission.
6. Green = the artifact is visible where it should be: the build in TestFlight ("Ready to Submit"), the release on the Play track, the release in Firebase App Distribution. A green job with no artifact is not green (troubleshooting F-14).

Cap: if the same failure repeats after two fixes, stop, show the user the log and your hypothesis, and ask.

## Phase 6 — Runbook and hand-off

Write `docs/release/ci-runbook.md` from `references/runbook.md`: keep the stack sections that apply, drop the rest, fill **§10 AS-CONFIGURED STATE** with what was actually set (dates, names — never values), and §8 with the **billed compute minutes** from the first green Xcode Cloud build (ask the user to read it from the build's detail page) and the Android job's duration. Add to the project's `CLAUDE.md`: the trigger scheme, that the iOS pipeline is not under `.github/`, and the two `ci_scripts/` constraints. Final item for the user: install the build on a device and confirm one analytics event arrives — a green build proves the config, only an event proves the binary.

## What not to do

- Don't keep a macOS job in GitHub Actions "for tests" without saying it costs 10× per minute; Xcode Cloud has a Test action.
- Don't propose fastlane match / `.p12` / API-key uploads for a project going to Xcode Cloud — managed signing makes them dead weight.
- Don't pin the Xcode version by default; Apple removes old versions and pins rot. Offer it as a documented choice.
- Don't trust CocoaPods' "specs repository is too out-of-date" — the real error is above it.
- Don't write anything in the runbook you didn't see set; mark it `<<FILL>>`.
- Don't ask for, echo, or commit a secret value. Ever.

## Files

- `references/interview.md` — question bank, the three `on:` trigger blocks, secret-storage options.
- `references/runbook.md` — the universal runbook (copy, trim, fill).
- `references/xcode-cloud-console.md` — every console setting with rationale.
- `references/console-chrome-flow.md` — driving App Store Connect with Chrome, safely.
- `references/github-actions-play.md` — Android job + Play service account.
- `references/firebase-app-distribution.md` — Firebase for Android (Actions) and iOS (Xcode Cloud).
- `references/troubleshooting.md` — the failure catalogue.
- `assets/xcode-cloud/{flutter,native,react-native,common}/` — `ci_scripts` templates.
- `assets/github-actions/` — Android workflows (Flutter, Gradle) + `notify.sh` (Telegram/Slack).
- `scripts/detect_project.sh`, `scripts/check_ci_scripts.sh`, `scripts/watch_github_run.sh`.
