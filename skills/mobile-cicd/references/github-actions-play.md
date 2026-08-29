# Android on GitHub Actions → Google Play

## Why Linux, why this shape

Android builds don't need macOS. A Linux runner is billed at 1× (macOS is 10× against included minutes and ~10× the pay-as-you-go rate). The Android job also keeps Play upload and signing entirely in GitHub, which is fine: Play's upload key model (Play App Signing) means the keystore in secrets is an *upload* key, replaceable through Play Console if lost.

Templates: `assets/github-actions/release-android-flutter.yml` and `release-android-gradle.yml` (RN / native Android / KMP).

## One-time Play Console setup

1. **Play App Signing** must be enabled for the app (default for apps created after 2021). Check *Play Console → app → Setup → App signing*.
2. **Upload keystore.** If the project has none: `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. Keep the file out of git (`.gitignore` it); base64 it into the secret.
3. **Service account.** Google Cloud Console → IAM & Admin → Service Accounts → create → Keys → Add key → JSON. Then Play Console → Users and permissions → Invite new users → the service account's email → App permissions → the app → *Release to testing tracks* (add *Release to production* only if the workflow will promote). Save; wait a few minutes.
4. **First upload by hand.** Play refuses API uploads for a package that has never had a manual upload. Upload one AAB through the console once.

## Secrets (names only — values go in repo → Settings → Secrets and variables → Actions)

| Secret | Content |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | |
| `ANDROID_KEY_ALIAS` | e.g. `upload` |
| `ANDROID_KEY_PASSWORD` | |
| `PLAY_SERVICE_ACCOUNT_JSON` | the whole JSON key file content |
| app config keys (e.g. `ANALYTICS_API_KEY`) | same values as the Xcode Cloud env — two copies, rotate both |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` (optional) | notifications |

Consider a GitHub **Environment** named `production` with required reviewers for the production track; internal-track releases don't need it.

## Job outline

```
on: push: tags: ['android/v*']
runs-on: ubuntu-latest
steps:
  checkout
  tag ↔ version guard (fail fast)
  setup-java 17 (Temurin)
  setup toolchain (flutter-action with cache / setup-node with cache)
  decode keystore → android/upload-keystore.jks; write android/key.properties
  synthesize .env / dart-defines from secrets; required-key gate
  build AAB with versionCode = GITHUB_RUN_NUMBER + OFFSET
  upload-google-play (track: internal, status: completed)
  notify DEPLOYED / FAILED
```

`OFFSET` exists because `github.run_number` restarts if the workflow file is renamed, and must stay above the highest `versionCode` Play has ever seen for this package. Set it once from Play Console → Releases → latest versionCode, and record it in the runbook.

## Things that look right and aren't

- `runs-on: macos-latest` anywhere in `.github/workflows/` after the migration — costs 10×, and is either the rollback path or a leak. `scripts/check_ci_scripts.sh` warns.
- `status: completed` on a brand-new app before the first manual upload — use `draft` for that one run.
- `flutter build appbundle` without `--build-number` — Gradle falls back to `pubspec.yaml`'s `+N`, which the runbook says not to bump by hand.
- Mapping/symbol files: pass `mappingFile:` (Flutter: `build/app/outputs/mapping/release/mapping.txt`) to the upload step so Play can symbolicate crashes; the template does.
