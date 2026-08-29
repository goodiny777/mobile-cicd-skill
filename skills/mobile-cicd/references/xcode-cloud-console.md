# Xcode Cloud console — every setting, with the reason

Walk this top to bottom with the user. First-time workflow creation is Xcode-only (Xcode → Product → Xcode Cloud → Create Workflow, or the Cloud tab in the Report Navigator); everything below is then editable at **App Store Connect → Apps → *app* → Xcode Cloud → Manage Workflows**.

Record what was actually chosen in the project runbook §10, with a date. Never record a secret value.

## A. Before the console

| Check | How | Why |
|---|---|---|
| App record exists in App Store Connect | ASC → Apps | Xcode Cloud attaches to an app; it can't create one |
| Scheme is shared and has an Archive action on Release | `ls <proj>/xcshareddata/xcschemes/`, open the `.xcscheme`, look for `<ArchiveAction buildConfiguration="Release"` | Xcode Cloud only sees shared schemes; `scripts/detect_project.sh` reports this |
| Project uses automatic signing | `grep -c 'CODE_SIGN_STYLE = Automatic' *.xcodeproj/project.pbxproj`, `DEVELOPMENT_TEAM` set | Managed signing needs it; leave it that way and delete any `sed` that flips it in old CI |
| `ci_scripts/` in the right directory | next to the `.xcworkspace`/`.xcodeproj` the workflow points at (`ios/ci_scripts/` for Flutter/RN) | Apple looks in exactly one place |

## B. Workflow settings

| # | Setting | Value | Why |
|---|---|---|---|
| 1 | Name | `iOS Release (TestFlight)` | Stable name → stable log links and runbook references |
| 2 | Enabled | on | |
| 3 | Primary Repository | this repo through the Xcode Cloud GitHub App | If tag pushes never start builds, the binding is stale: **New Primary Repository** → re-select → wait for "Access Granted". Granting the App access on GitHub alone does not refresh an existing binding. |
| 4 | Project or Workspace | `ios/Runner.xcworkspace` (Flutter/RN) · `App.xcodeproj` or `.xcworkspace` (native) | |
| 5 | **Environment → Xcode Version** | **Latest Release** (default). Pin only as a documented, dated choice. | Apple removes old Xcode versions from Xcode Cloud (all 15.x/16.x went on one day). A pin eventually becomes invalid and breaks in a harder-to-diagnose way than an upgrade. Apple's SDK-minimum mandate (iOS 26 SDK since 2026-04-28) means the toolchain must move anyway. |
| 6 | Environment → macOS Version | Latest Release | Same reasoning |
| 7 | **Environment → Clean** | **Off** for internal TestFlight. **On** only for external TestFlight, where Apple requires it. | Clean discards derived data and caches on every build — Apple's own wording: "significantly increases build time". It was **on** in the default workflow. Every extra minute is billed. |
| 8 | Environment → Environment Variables | The names from the runbook §3.1. Tick **Keep value redacted** on secrets. | Redaction makes the console show asterisks and masks the value in logs. The scripts never print values anyway; this is defence in depth. |
| 9 | **Start Conditions** | **Tag Changes → Custom Tags → "Tags beginning with `ios/v`"**. **Delete** the default *Branch Changes → main*. | Branch builds start on every push, including doc-only commits, and each is a full billed archive. The tag prefix keeps `android/v*` from starting an iOS build. |
| 10 | Auto-cancel builds (on the tag condition) | off | A release should never be cancelled because the next tag arrived |
| 11 | Manual Start | may stay at "Any Tags" / any branch | This is the hand-start path; building an arbitrary ref there is useful, not harmful |
| 12 | Actions | **Archive – iOS**, Platform iOS, Scheme = the shared scheme | Add a Test action only if you want tests billed on Apple minutes; it runs in parallel with Archive |
| 13 | **Archive → Distribution Preparation** | **TestFlight (Internal Testing Only)** — or *TestFlight and App Store* for external / release | This *is* the upload. No App Store Connect API key, no `altool`. |
| 14 | Post-Actions → TestFlight Internal Testing | the tester group | |
| 15 | Post-Actions → Notify → Email | the owner's Apple ID email | `ci_post_xcodebuild.sh` runs *before* delivery and can't see export-compliance or processing failures. The email is the only thing that reports those. |
| 16 | Signing | leave managed; nothing to upload | |

## C. App-level Xcode Cloud settings

| Setting | Where | Guidance |
|---|---|---|
| Next Build Number | ASC → app → Xcode Cloud → Settings → Build Number | iOS does **not** need build numbers to increase across versions, only `(version, build)` uniqueness. Leaving the default is correct. Set it above the last CI's build number only if you want a monotonic history, and record the value in the runbook. Mac apps *do* need monotonic numbers. |
| Usage | ASC → Xcode Cloud → Usage | Check monthly. Record billed minutes of the first green build in runbook §8. |

## D. Verification after configuring

1. The workflow appears both in ASC and in Xcode's Report Navigator → Cloud.
2. The three secret variables render as asterisks in the Environment tab.
3. Push `ios/vX.Y.Z` for a version that matches the project. A build starts within a minute. If nothing starts, see #3 above before anything else.
4. First run: expect failures in `ci_post_clone.sh` before anything in Apple's own steps. Read `troubleshooting.md`.
