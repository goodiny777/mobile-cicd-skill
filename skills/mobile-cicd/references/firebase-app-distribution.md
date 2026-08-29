# Firebase App Distribution

Use when the owner wants builds in testers' hands without Play/TestFlight review latency, or for external testers on iOS without Clean = on.

## One-time setup (both platforms)

1. Firebase project with the Android app (package name) and/or iOS app (bundle id) registered.
2. Service account: Google Cloud → IAM → Service Accounts → create → grant role **Firebase App Distribution Admin** → Keys → JSON. Store the JSON content as a secret; never commit it.
3. Tester groups: Firebase Console → App Distribution → Testers & Groups → create group(s); note the group **aliases** (not display names).
4. iOS only: testers' device UDIDs must be registered in the Apple Developer team (App Distribution collects them; you add them under Devices) so the ad-hoc profile includes them. Managed signing regenerates the profile automatically once devices are in the team.

## Android — GitHub Actions step

Secret: `FIREBASE_SERVICE_ACCOUNT_JSON`. Add after the AAB/APK build (Firebase accepts AAB when the app is linked to Play, otherwise build an APK: `flutter build apk --release` / `./gradlew assembleRelease`).

```yaml
      - name: Firebase App Distribution
        if: env.DEPLOY_FIREBASE == 'true'
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_ANDROID_APP_ID }}       # 1:1234…:android:abcd — from Firebase project settings; not a secret, but keep it out of the workflow anyway
          serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_JSON }}
          groups: ${{ env.FIREBASE_GROUPS }}                   # comma-separated aliases, e.g. qa,internal
          file: build/app/outputs/flutter-apk/app-release.apk # or the AAB path
          releaseNotes: "${{ github.ref_name }} — ${{ github.sha }}"
```

Add `DEPLOY_FIREBASE: 'true'` and `FIREBASE_GROUPS: 'qa'` to the workflow `env:`.

## iOS — Xcode Cloud `ci_post_xcodebuild.sh`

Xcode Cloud can export an ad-hoc signed IPA alongside the App Store one; it appears under `CI_AD_HOC_SIGNED_APP_PATH` in the post-xcodebuild phase when the archive action's export includes ad hoc. Check the build's *Artifacts* tab once to confirm the export exists before relying on it.

Console env vars: `FIREBASE_SERVICE_ACCOUNT_JSON` (secret, redacted — the whole JSON on one line), `FIREBASE_IOS_APP_ID`, `FIREBASE_GROUPS`.

Block to append to `ci_post_xcodebuild.sh` after the ARCHIVED notification:

```bash
if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" = "0" ] && [ -n "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ] && [ -n "${CI_AD_HOC_SIGNED_APP_PATH:-}" ]; then
  IPA="$(find "$CI_AD_HOC_SIGNED_APP_PATH" -name '*.ipa' | head -1)"
  if [ -n "$IPA" ]; then
    echo "[post-xcodebuild] distributing $(basename "$IPA") via Firebase App Distribution"
    command -v firebase >/dev/null 2>&1 || curl -sL https://firebase.tools | bash >/dev/null
    CRED="$(mktemp)"; printf '%s' "$FIREBASE_SERVICE_ACCOUNT_JSON" > "$CRED"
    GOOGLE_APPLICATION_CREDENTIALS="$CRED" firebase appdistribution:distribute "$IPA" \
      --app "$FIREBASE_IOS_APP_ID" --groups "${FIREBASE_GROUPS:-}" \
      --release-notes "${CI_TAG:-manual} build ${CI_BUILD_NUMBER:-?}" \
      && notify "DISTRIBUTED" "Firebase App Distribution, build ${CI_BUILD_NUMBER:-?}" \
      || notify "FAILED" "Firebase App Distribution upload"
    rm -f "$CRED"
  else
    echo "[post-xcodebuild] no ad-hoc IPA found under CI_AD_HOC_SIGNED_APP_PATH — check the archive export settings"
  fi
fi
```

Here the word `DISTRIBUTED` is honest — the upload happened in this script. `ARCHIVED` stays for TestFlight.

## Failure notes

- `403 PERMISSION_DENIED` → service account lacks *Firebase App Distribution Admin* on this project.
- "App not found" → the `appId` belongs to another Firebase project or platform.
- iOS testers can't install → UDID not in the team / ad-hoc profile; re-archive after adding the device.
- Both platforms: the `groups` value is the **alias**, not the group's display name.
