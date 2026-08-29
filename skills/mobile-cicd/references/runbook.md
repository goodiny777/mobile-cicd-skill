# Mobile CI/CD Runbook — Xcode Cloud (iOS) + GitHub Actions (Android)

**Applies to:** native iOS (Swift/SwiftUI/UIKit), Flutter, React Native, Kotlin Multiplatform.
**Targets:** TestFlight (internal or external) and Google Play (internal / closed / production tracks); optionally Firebase App Distribution on either platform (Android from the Actions job, iOS from `ci_post_xcodebuild.sh` using the ad-hoc export).
**Shape of the result:** iOS builds run on Xcode Cloud with managed signing and three optional `ci_scripts`; Android builds run on a Linux GitHub Actions runner. Each platform is released by its own git tag prefix. Nothing secret is committed anywhere.

This document is written to be copied into a project (`docs/release/ci-runbook.md`), then filled in. Every `<<FILL: …>>` is a value only the project owner can supply. Keep it updated the same day you change a console setting — the Xcode Cloud workflow lives outside git, and this file is its only in-repo record.

---

## Contents

0. Prerequisites and roles
1. Decide the shape (decision table)
2. Release tag scheme
3. Secrets — where each one lives (never values)
4. iOS on Xcode Cloud — console configuration
5. iOS `ci_scripts/` — what each does, per stack
6. Android on GitHub Actions — workflow and Play upload
7. First live run — the harness and the expected failure list
8. Compute-hour economics — measure, don't estimate
9. Rollback
10. AS-CONFIGURED STATE (fill after setup)
11. Troubleshooting index

---

## 0. Prerequisites and roles

| Need | Why |
|---|---|
| Apple ID with **Admin** or **App Manager** on the App Store Connect team | Create/edit Xcode Cloud workflows, set Next Build Number, manage TestFlight groups |
| A Mac with Xcode, **once** | Apple requires the *initial* Xcode Cloud workflow creation from inside Xcode. All later edits work in the App Store Connect web UI. |
| Owner/admin of the GitHub repository (or org) | Approve the Xcode Cloud GitHub App installation; create repository secrets |
| Google Play Console **Admin** (or a role that can manage API access) | Create a service account and grant it release rights on the app |
| The app record already exists in App Store Connect and Play Console | Xcode Cloud attaches to an app; Play upload needs a package name that has had at least one manual upload |

---

## 1. Decide the shape

| Question | Native iOS | Flutter | React Native | KMP |
|---|---|---|---|---|
| Need `ci_scripts/` at all? | Only for notifications / env injection | **Yes** — Apple's image has no Flutter SDK | **Yes** — needs Node + `npm ci` + pods | Usually yes — Gradle shared module must build before Xcode |
| Where `ci_scripts/` lives | `<project-root>/ci_scripts/` (next to `.xcodeproj`/`.xcworkspace`) | `ios/ci_scripts/` | `ios/ci_scripts/` | `iosApp/ci_scripts/` (or wherever the Xcode project is) |
| Dependency manager Apple must run | SPM (auto) or CocoaPods | CocoaPods via `flutter build ios --config-only` (SPM needs committed `Package.resolved`) | CocoaPods (`pod install` after `npm ci`) | SPM/CocoaPods for iOS + Gradle for shared |
| Compile-time config injection | xcconfig / Info.plist from env | `--dart-define-from-file=.env` | `react-native-config` `.env` | BuildKonfig / Gradle properties |
| Android runner | n/a | `ubuntu-latest` | `ubuntu-latest` | `ubuntu-latest` |
| TestFlight audience | Internal → Clean **off**. External → Clean **on** (Apple requires it) | same | same | same |
| Trigger rule | tag prefix (default) · branch · manual (`workflow_dispatch` / Xcode Cloud Manual Start) — decide once, document in §10 | same | same | same |

**Rule that holds for all four:** Xcode Cloud handles signing and TestFlight upload; GitHub Actions handles Android and nothing Apple-related. Don't keep a macOS job in Actions "just in case" — it costs 10× and is exactly the rollback path this runbook describes in §9.

---

## 2. Release tag scheme

```
ios/vX.Y.Z      → starts the Xcode Cloud workflow
android/vX.Y.Z  → starts the GitHub Actions Android job
vX.Y.Z          → triggers NOTHING on either platform (deliberate)
```

Why prefixes and not one tag: the two platforms now live on different CI systems with different failure modes and different costs. Independent tags let you re-cut one platform without rebuilding the other. The bare tag is a deliberate no-op so a habit from before the split fails silently and free, not expensively.

**Version guard.** `ci_post_clone.sh` (iOS) and the Android workflow both compare the tag's `X.Y.Z` to the version declared in the project (`pubspec.yaml` `version:`, `MARKETING_VERSION`, `package.json`, or `gradle.properties`) and fail immediately on mismatch. This is the cheapest check in the pipeline and prevents shipping `1.0.4` under a `1.0.3` tag.

**Build numbers.** iOS: `CI_BUILD_NUMBER` from Xcode Cloud (or set Next Build Number in ASC → Xcode Cloud → Settings if you need to jump above an old value). iOS does *not* require build numbers to increase across versions — only `(version, build)` uniqueness. Android: `versionCode` from `github.run_number` plus an offset that keeps it above the last Play upload.

Release procedure:

```sh
# 1. bump version, commit, push
# 2. tag whichever platform(s) you're releasing
git tag ios/v1.2.0 && git push origin ios/v1.2.0
git tag android/v1.2.0 && git push origin android/v1.2.0
```

Where to watch: iOS → App Store Connect → Xcode Cloud → Builds (or Xcode → Report Navigator → Cloud). Android → GitHub → Actions.

---

## 3. Secrets — where each one lives

This runbook never contains a secret value. It records **the name, the console location, and every place a copy exists**, so a rotation updates all of them.

### 3.1 Xcode Cloud (iOS)

Path: **App Store Connect → Apps → *your app* → Xcode Cloud → Manage Workflows → *workflow* → Environment → Environment Variables**. For every secret tick **"Keep value redacted"** so the value renders as asterisks in the console and in logs.

| Variable | Secret? | Purpose | Also lives in |
|---|---|---|---|
| `<<FILL: e.g. ANALYTICS_API_KEY>>` | yes | compile-time key injected into the binary | GitHub Actions secret of the same name (Android needs it too) → **two copies, rotate both** |
| `TELEGRAM_BOT_TOKEN` / `SLACK_WEBHOOK_URL` | yes | build notifications; scripts skip silently if unset | GitHub Actions secret |
| `TELEGRAM_CHAT_ID` | yes (treat as secret) | notification target | GitHub Actions secret |
| `FLUTTER_VERSION` / `NODE_VERSION` | no | toolchain pin for `ci_post_clone.sh` | `.github/workflows/*.yml` env — keep equal |
| feature flags (`PREMIUM_UNLOCKED`, …) | no | build-time defaults | workflow env |

Enter these by hand in the console. Do not paste them into chat, commit messages, or a script.

### 3.2 GitHub Actions (Android)

Path: **repository → Settings → Secrets and variables → Actions → New repository secret** (or *Environment secrets* if you use a `production` environment with required reviewers).

| Secret | Purpose | How to produce |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | upload keystore | Linux/Git Bash: `base64 -w0 upload-keystore.jks`; macOS: `base64 -i upload-keystore.jks \| tr -d '\n'`; PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks"))`. The workflow decodes it to a temp file and scrubs it. |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | keystore credentials | as created with `keytool` |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play Developer API | Google Cloud → IAM → Service Accounts → Keys → JSON; then Play Console → Users and permissions → invite the service-account email → grant *Release to testing tracks* (and production if needed) on the app |
| `<<FILL: ANALYTICS_API_KEY>>` | same key as iOS | copy of the Xcode Cloud value |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | notifications | copy of the Xcode Cloud values |

### 3.3 The six Apple secrets you can now delete (but not yet)

If you are migrating *from* a hand-rolled Actions iOS job, these exist and form your rollback (§9). Delete them only after the first Xcode Cloud release is green, and record the deletion date in §10.

`IOS_DISTRIBUTION_CERT_P12_BASE64`, `IOS_DISTRIBUTION_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_BASE64`.

### 3.4 Script-side discipline

Regardless of console redaction, scripts log presence only: `KEY present (N characters) — value not logged`. Any `.env` echoed to the log shows `<redacted, N chars>`. A missing **required** key fails the build in `ci_post_clone.sh` (before any compile minute is spent); a missing **optional** key (notifications) is a one-line warning.

---

## 4. iOS on Xcode Cloud — console configuration

Do these in order. First-time workflow creation happens in Xcode (Product → Xcode Cloud → Create Workflow); everything after that is editable at App Store Connect → Xcode Cloud → Manage Workflows.

| # | Setting | Value | Why |
|---|---|---|---|
| 1 | Workflow name | `iOS Release (TestFlight)` | keep stable — this runbook and log links reference it |
| 2 | Primary Repository | this repo, via the Xcode Cloud GitHub App | if builds never start, see §11 T-1 — the binding can go stale |
| 3 | Project / Workspace | `ios/Runner.xcworkspace` (Flutter/RN) or `App.xcodeproj` (native) | |
| 4 | Scheme | your **shared** scheme with `ArchiveAction` on `Release` | Xcode Cloud can't see unshared schemes; check `xcshareddata/xcschemes/` |
| 5 | Environment → Xcode Version | **Latest Release** (default) — or a pin, recorded in §10 with date | Apple removes old Xcodes from the picker; pins rot. Latest satisfies the iOS SDK minimum mandate automatically. |
| 6 | Environment → macOS Version | Latest Release | |
| 7 | Environment → **Clean** | **Off** for internal TestFlight; **On** only for external | Clean discards derived data and cache; Apple: "significantly increases build time" |
| 8 | Environment Variables | see §3.1 | |
| 9 | Start Conditions | **Tag Changes → Custom → "Tags beginning with `ios/v`"**. Delete the default *Branch Changes → main*. | branch builds burn compute on doc commits |
| 10 | Auto-cancel builds | off on the tag condition | a release tag should never be cancelled by the next one |
| 11 | Action | **Archive – iOS**, Platform iOS | |
| 12 | Distribution Preparation | **TestFlight (Internal Testing Only)** (or External if you accept Clean=On) | this is the upload — no API key needed |
| 13 | Post-Actions → TestFlight Internal Testing | your tester group | |
| 14 | Post-Actions → Notify (Email) | owner address | the only thing that reports a *post-archive* delivery failure — `ci_post_xcodebuild.sh` runs before delivery and can't see it |
| 15 | Signing | leave **managed**; keep `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = <<FILL>>` in the project | no certificates, profiles, or keychains anywhere |
| 16 | Manual Start condition | may stay on "Any Tags" | the hand-start path; building an arbitrary ref there is useful |

Record what you actually set in §10.

---

## 5. iOS `ci_scripts/` — what each does

Apple runs, if present and executable: `ci_post_clone.sh` → (your Archive action's xcodebuild) with `ci_pre_xcodebuild.sh` just before and `ci_post_xcodebuild.sh` just after. Environment variables available: `CI_TAG`, `CI_BUILD_NUMBER`, `CI_WORKSPACE_PATH` (or `CI_PRIMARY_REPOSITORY_PATH`), `CI_XCODEBUILD_EXIT_CODE` (post only), plus everything you set in §3.1.

Two constraints that bite, both fixed at commit time and both checked by the harness in §7:

- Scripts must be `100755` **in the git index**, not just on disk — matters on Windows and on any machine with `core.filemode=false`. Use the skill's `scripts/fix_exec_bits.sh` (or `.ps1`); a hand-typed `git update-index --chmod=+x dir/*.sh` silently does nothing in PowerShell because the glob is not expanded.
- Scripts must have **LF** endings. Add to `.gitattributes`: `*.sh text eol=lf`.

Apple does **not** wipe generated files between post-clone and archive (`Generated.xcconfig`, `Pods/`, `node_modules/` survive), so post-clone can do all preparation.

### 5.1 `ci_post_clone.sh` by stack

| Step | Native | Flutter | React Native | KMP |
|---|---|---|---|---|
| Toolchain | — | `git clone --depth 1 -b $FLUTTER_VERSION https://github.com/flutter/flutter.git`; `flutter precache --ios` | `brew install node@<major>` or nvm; `npm ci` | `brew install openjdk@17`; Gradle wrapper |
| Deps | `pod install` if CocoaPods | `flutter pub get` | `pod install` in `ios/` | `./gradlew :shared:embedAndSignAppleFrameworkForXcode` prerequisites |
| Tag ↔ version guard | compare `CI_TAG` to `MARKETING_VERSION` | to `pubspec.yaml` `version:` | to `package.json` | to `gradle.properties` |
| Config injection | write `Config.xcconfig` from env | write `.env`, then `flutter build ios --config-only --release --dart-define-from-file=.env` (this also runs `pod install` — **don't run it twice**) | write `.env` for `react-native-config` | write `local.properties` / BuildKonfig |
| Required-key gate | fail if unset | fail if unset | fail if unset | fail if unset |
| Notify | `STARTED` | `STARTED` | `STARTED` | `STARTED` |

### 5.2 `ci_pre_xcodebuild.sh`

Verify the injected config actually reached the build inputs. Flutter: base64-decode `DART_DEFINES` from `ios/Flutter/Generated.xcconfig` and assert the required key is non-empty. Native: assert the xcconfig line exists. This gate converts a silent runtime failure (analytics never fires) into a loud build failure. It costs a second.

### 5.3 `ci_post_xcodebuild.sh`

Read `CI_XCODEBUILD_EXIT_CODE`; send `ARCHIVED` or `FAILED` with version and `CI_BUILD_NUMBER`. Say `ARCHIVED`, never `DEPLOYED` — delivery happens after this script.

Templates for all three, per stack, are in the skill's `assets/xcode-cloud/`.

---

## 6. Android on GitHub Actions

Workflow: `.github/workflows/release-android.yml`, `on.push.tags: ['android/v*']`, `runs-on: ubuntu-latest`. Structure:

1. Checkout; tag ↔ version guard.
2. Toolchain: `actions/setup-java@v4` (Temurin 17), plus `subosito/flutter-action@v2` (Flutter, with `cache: true`) or `actions/setup-node@v4` (RN).
3. Decode keystore: `echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/upload-keystore.jks`; write `android/key.properties` from the three credential secrets.
4. Synthesize `.env` / dart-defines from secrets — same required-key gate as iOS.
5. Build the AAB: `flutter build appbundle --release --build-number=$((GITHUB_RUN_NUMBER + OFFSET))` or `./gradlew bundleRelease`.
6. Upload: `r0adkll/upload-google-play@v1` with `serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}`, `track: internal`, `status: completed` (or `draft` for a first upload of a new app).
7. Notify `DEPLOYED` — here the word is accurate, because the upload step ran in the same job.

Cost note: this job runs ~4–6 minutes on Linux at the 1× multiplier. There should be **no** macOS runner anywhere in `.github/workflows/` after the migration — if `grep -r macos .github/workflows` finds one, it is either the rollback path (§9) or a leak.

The template is in the skill's `assets/github-actions/release-android.yml`.

---

## 7. First live run — the harness and the expected failure list

Before pushing the first `ios/v*` tag, run the local harness (`scripts/check_ci_scripts.sh` in the skill):

- every `ci_scripts/*.sh` is `100755` in the index and LF-terminated;
- `bash -n` passes on each;
- `shellcheck` if available;
- the scheme is shared and has an Archive action;
- no macOS runner remains in `.github/workflows/` (warning);
- no string that looks like a key (`AKIA`, long hex, `-----BEGIN`) is committed under `ci_scripts/` or `.github/`.

Then expect **3–8 hot-fix commits**. Observed on a real first run, in order, with the fixes (all pre-existing defects, none in the migration itself):

| Symptom | Actual cause | Fix |
|---|---|---|
| No build starts from any tag | Repository binding created before the GitHub App had access → stale | Xcode Cloud → workflow → **New Primary Repository**, wait for "Access Granted" |
| `pub get` / `npm ci` fails | toolchain pin in CI older than what the lockfile needs | align `FLUTTER_VERSION` / `NODE_VERSION` env with the project; this was breaking Android too |
| SPM resolution fails | Xcode Cloud disables automatic resolution; needs committed `Package.resolved` | commit it (from a Mac) or fall back to CocoaPods |
| "specs repository is too out-of-date" | generic CocoaPods fallback — **not the real error** | read the lines above it |
| `require 'xcodeproj'` LoadError in a podspec | podspec Ruby helper runs under system Ruby; CocoaPods is Homebrew's | `gem install --user-install xcodeproj` in post-clone |
| Pod resolver conflict | `Podfile.lock` months stale vs new plugin versions | regenerate on a Mac and commit; until then the script deletes the lock (reproducibility loss — track it) |
| Duplicate `pod install` | `flutter build --config-only` already runs it | remove the explicit call |

After the green build: install from TestFlight on a real device and confirm one analytics event arrives. A green build proves the config reached the build; only a received event proves it reached the binary.

---

## 8. Compute-hour economics — measure, don't estimate

Fill this after the first green run, from App Store Connect → Xcode Cloud → the build's detail page ("Usage").

| Metric | Value |
|---|---|
| Xcode Cloud included tier | 25 compute-hours / month (Apple Developer Program); paid tiers 100 h $49.99, 250 h $99.99, 1000 h $399.99 |
| Billed compute per iOS release | `<<FILL after first run>>` (reference project, Flutter, no Clean: **6 min** for a 10-min wall clock) |
| Releases/month headroom | 25 h ÷ billed minutes (reference: ~250) |
| GitHub Actions macOS minutes per iOS release, before | reference: ~45 (4.5 min × 10× multiplier) |
| GitHub Actions macOS minutes, after | 0 |
| Android Linux minutes per release | `<<FILL>>` (typically 4–6, at 1×) |

Watch monthly: App Store Connect → Xcode Cloud → Usage; GitHub → Settings → Billing → Actions.

Note: the first Xcode Cloud build has no cache and may run slower than steady state — if the first figure is well above expectation, take a second measurement before revising anything.

---

## 9. Rollback

- **iOS:** `git revert` the commit that removed the iOS job from `.github/workflows/`. This works only while the six Apple secrets (§3.3) still exist. After they are deleted, rollback means re-exporting the certificate and profile from a Mac and re-adding all six.
- **Android:** unchanged by this migration; rollback is a normal workflow revert.
- **Console-side:** Xcode Cloud workflows can be disabled (not deleted) with one toggle — prefer that while diagnosing.

---

## 10. AS-CONFIGURED STATE

Fill this in after walking §4 and §6. Date every line. This section is what the next person reads first.

| Item | Value | Set on |
|---|---|---|
| Workflow name | `<<FILL>>` | |
| Xcode / macOS | `<<FILL: Latest Release or pinned X.Y (build)>>` | |
| Clean | `<<FILL: off/on>>` | |
| Start condition | `<<FILL: Tags beginning with ios/v>>` | |
| Distribution Preparation | `<<FILL>>` | |
| Tester group | `<<FILL>>` | |
| Email post-action recipients | `<<FILL>>` | |
| Env vars present (names only) | `<<FILL>>` | |
| Secrets ticked "Keep value redacted" | `<<FILL: names>>` | |
| GitHub App access granted | `<<FILL: date>>` | |
| Next Build Number | `<<FILL: default / value>>` | |
| Android secrets present (names only) | `<<FILL>>` | |
| Play service account email | `<<FILL: name only>>` | |
| First green iOS build | `<<FILL: build #, tag, billed minutes>>` | |
| Six Apple GitHub secrets deleted | `<<FILL: date or "not yet">>` | |

---

## 11. Troubleshooting index

| Code | Symptom | See |
|---|---|---|
| T-1 | Tag pushed, nothing starts | §7 row 1 — stale repository binding |
| T-2 | Build starts from every push to main | §4 #9 — delete Branch Changes condition |
| T-3 | Build takes 2× longer than expected | §4 #7 — Clean is on |
| T-4 | `ci_scripts` not executed, no log lines from them | §5 — `100755` in index / LF endings / wrong directory |
| T-5 | "too out-of-date" from CocoaPods | §7 — read above the line; Ruby `xcodeproj` |
| T-6 | SPM "requires Package.resolved" | §7 — commit it or use CocoaPods |
| T-7 | Archive OK, nothing in TestFlight | §4 #12/#14 — Distribution Preparation unset; check email post-action |
| T-8 | Analytics silent in the installed build | §5.2 gate; §7 device check |
| T-9 | Android upload rejected: versionCode already used | §2 — raise the offset |
| T-10 | Play API 403 | §3.2 — service account not invited to the app in Play Console |
| T-11 | Secret visible in a log | §3.4 — script echoed it; rotate, then fix the script |
