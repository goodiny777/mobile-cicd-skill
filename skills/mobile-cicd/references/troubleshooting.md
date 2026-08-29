# Troubleshooting catalogue

Ordered by how early in a run the symptom appears. Every entry was observed on a real first live run unless marked *anticipated*. "Real cause" is what the log actually meant, which is often not what it said.

## Nothing starts

**F-1 · Tag pushed, no build.**
Real cause: the Xcode Cloud repository binding was created before the GitHub App had access, and stayed stale. Granting the App access afterwards on GitHub does **not** refresh it.
Fix: ASC → workflow → *New Primary Repository* → pick the repo → wait for "Access Granted". The next tag fires immediately.
Also check: the tag actually matches the start-condition prefix (`ios/v` vs `ios/V`); the workflow is enabled; the tag was pushed (`git ls-remote --tags origin`).

**F-2 · Build starts on every push to main.** Default workflow ships with *Branch Changes → main*. Delete it; keep only Tag Changes.

## `ci_scripts` never run

**F-3 · No `ci_post_clone.sh` lines in the log.**
Real cause: not executable in the git index, CRLF endings, or wrong directory.
Check: `git ls-files -s ios/ci_scripts/` shows `100755`; `git show HEAD:ios/ci_scripts/ci_post_clone.sh | file -` says no CRLF; the directory sits beside the workspace the workflow points at. `scripts/check_ci_scripts.sh` tests all three. Windows authors: `core.filemode=false` hides the bit on disk — always check the index.

## Dependency phase (`ci_post_clone.sh`)

**F-4 · `flutter pub get` / `npm ci` fails on version constraints.**
Real cause: CI toolchain pin older than the lockfile needs (Flutter's `flutter_localizations` pins `intl`; a project `intl` bump two days before the release broke it). **This breaks the Android job identically** — it just hadn't been tagged.
Fix: align `FLUTTER_VERSION` / `NODE_VERSION` in the Xcode Cloud env and the Actions workflow env with what the project needs; keep both equal.

**F-5 · Swift Package Manager: "automatic resolution disabled" / missing `Package.resolved`.**
Real cause: Xcode Cloud disables automatic SPM resolution and requires a committed `Package.resolved`. Recent Flutter routes plugins through SPM.
Fix: on a Mac, resolve once and commit `Package.resolved`; or disable Flutter's SPM (`flutter config --no-enable-swift-package-manager`) and use CocoaPods until you can.

**F-6 · CocoaPods: "The specs repository is too out-of-date".**
**This is not the error.** It's CocoaPods' generic fallback whenever a podspec fails to evaluate. `pod repo update` will not help.
Fix: scroll up. The real error is usually F-7 or F-8.

**F-7 · Podspec fails with `cannot load such file -- xcodeproj` (LoadError).**
Real cause: a plugin's podspec runs a Ruby helper with `require 'xcodeproj'` under **system Ruby** (2.6 on Apple's image), while CocoaPods is Homebrew-installed with gems under Homebrew's Ruby.
Fix in `ci_post_clone.sh` before the dependency step: `gem install --user-install xcodeproj` (the templates include it, guarded).

**F-8 · Pod resolver conflict (`CocoaPods could not find compatible versions for pod "X"`).**
Real cause: `ios/Podfile.lock` months stale; a plugin version bump (via `pubspec.lock` / `package-lock.json`) wants a different native SDK than the lock records. **Also breaks local Mac builds.**
Fix: on a Mac, `cd ios && pod install --repo-update`, commit the lock. Until then the template can delete the stale lock (`rm -f ios/Podfile.lock`) — flag this in the runbook as a reproducibility loss to close.

**F-9 · `pod install` runs twice, second run fails or wastes minutes.**
Real cause: `flutter build ios --config-only` already runs `pod install`; an explicit call afterwards is redundant. Remove it.

**F-10 · Required key missing → build fails in the first seconds.**
Working as designed. The variable isn't set in the workflow's Environment Variables, or is set on a different workflow. Add it in the console (name from the runbook §3.1). Never work around it by defaulting to an empty string.

## Archive phase

**F-11 · `ci_pre_xcodebuild.sh` gate fails: key empty in `Generated.xcconfig`.**
Real cause: `.env` was written after the config-only build, or `--dart-define-from-file` pointed at the wrong path. Order in the template is: write `.env` → config-only build → gate.

**F-12 · Signing error despite automatic signing.**
Real cause (anticipated): `DEVELOPMENT_TEAM` missing on one target (extensions, widgets), or a target still on manual signing from old CI's `sed`. `grep -n 'CODE_SIGN_STYLE' project.pbxproj` — all targets Automatic.

**F-13 · Export archive fails for *development* distribution on a specific Xcode.**
Apple's release notes have listed this for individual Xcode versions. TestFlight/App Store exports are unaffected. If you actually need development distribution, pin one minor lower and record it.

## After the archive

**F-14 · Archive succeeded, nothing appears in TestFlight.**
Real cause: *Distribution Preparation* is "None", or the TestFlight post-action has no group, or processing/export-compliance failed. `ci_post_xcodebuild.sh` cannot see any of this — it ran before delivery. Check the email notification post-action; if none is configured, add one.

**F-15 · Green build, analytics silent on device.**
The gate proved the key reached the config, not the binary. Install from TestFlight, trigger one event, confirm it in the analytics backend. If absent: the dart-define / xcconfig isn't read by the code path you think — check how the app reads it at runtime.

## Android

**F-16 · Play upload: `versionCode` already used.** Raise the offset added to `GITHUB_RUN_NUMBER`.

**F-17 · Play API 403 / "The caller does not have permission".** The service account is created in Google Cloud but not invited in *Play Console → Users and permissions* with release rights on this app. Invitation propagation can take minutes.

**F-18 · First API upload of a brand-new app rejected.** Play requires at least one manual AAB upload before API uploads; do it once by hand, then re-run.

## Hygiene

**F-19 · A secret value appears in a log.** Rotate it first (both copies — Xcode Cloud env and GitHub secret), then fix the script that echoed it. Tick *Keep value redacted* so the console masks it next time.

**F-20 · Silence after pushing a bare `vX.Y.Z` tag.** Not a failure. The bare tag is a deliberate no-op; push `ios/vX.Y.Z` and/or `android/vX.Y.Z`.
