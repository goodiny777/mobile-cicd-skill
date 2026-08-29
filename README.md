# mobile-cicd — a skill that ships your mobile app

> Xcode Cloud for iOS · GitHub Actions for Android · TestFlight, Google Play, Firebase App Distribution · interview-driven · fixes the first build from logs until it's green.

`mobile-cicd` is an [Agent Skill](https://agentskills.io) — a folder of instructions, templates and scripts that an AI coding agent (Claude Code, Codex CLI, Gemini CLI, Cursor, or any LLM you can hand a folder to) loads on demand. Point it at a mobile repository and it takes the project from "no release pipeline" to a green first build on every platform you ask for, and leaves a runbook behind.

It was extracted from a real migration that cut the cost of an iOS release from **~45 GitHub-billed macOS minutes to 6 minutes of Xcode Cloud compute** (free under the 25 hours bundled with the Apple Developer Program) and hit seven distinct failures on the way — every one of which is now in the skill's failure catalogue so the next person recognises it in seconds. The story: [English](https://medium.com/@goodiny777) · [Russian](https://habr.com/ru/users/goodiny777/).

---

## What it does

| Phase | What happens |
|---|---|
| **0 · Detect** | `detect_project.sh` reads the repo: native iOS / native Android / Flutter / React Native / KMP, which modules exist, submodules, shared Xcode scheme and signing style, CocoaPods vs SPM and `Podfile.lock` age, Gradle `applicationId`, flavors, `signingConfigs`, `versionCode` wiring, existing workflows and whether any burn macOS minutes. |
| **1 · Interview** | One topic at a time: which platforms; deploy targets (Play track, TestFlight internal/external, App Store, Firebase App Distribution); trigger rule (tag prefix / branch / manual / all prepared); where secrets will live; notifications (Telegram or Slack); version source of truth. |
| **2 · Secrets** | Produces a *secrets map* — name → console location → every copy → required/optional. Guides you through entering values in GitHub and App Store Connect and verifies presence with `gh secret list`. **Never asks for, echoes, or commits a value.** |
| **3 · Generate** | Copies and adapts tested templates: Xcode Cloud `ci_scripts/` (fail-fast version guard, required-key gate, config injection, honest `ARCHIVED` notification) and a Linux-only Android workflow (keystore decode + scrub, Play upload, Firebase, Telegram/Slack). Runs `check_ci_scripts.sh` — index mode `100755`, LF endings, shellcheck, shared scheme, leftover macOS runners, key-shaped strings. |
| **4 · Console** | Walks you through every Xcode Cloud setting with the reason (Clean off, tag start condition, Distribution Preparation, email backstop, Latest Release vs pin). With the Claude in Chrome extension it can click through App Store Connect itself — but never types a secret and never deletes. |
| **5 · Push · watch · fix** | Commits, pushes, fires the trigger, watches the run (`watch_github_run.sh` / Xcode Cloud logs), matches the failure against the catalogue, fixes, pushes again. Expects 3–8 fix commits on a first live run and says so. Stops and asks if the same failure repeats twice. |
| **6 · Runbook** | Writes `docs/release/ci-runbook.md` with an *AS-CONFIGURED STATE* section (dates, names, never values) and the measured compute minutes, plus a `CLAUDE.md` note that the iOS pipeline lives outside `.github/`. |

Supported stacks: **native iOS (Swift)**, **native Android (Gradle)**, **Flutter**, **React Native**, **Kotlin Multiplatform**.

---

## Install

The skill is the folder `skills/mobile-cicd/`. Every agent below reads the same `SKILL.md`; only the directory differs.

### Claude Code

```bash
# as a plugin (recommended — gets updates)
/plugin marketplace add goodiny777/mobile-cicd-skill
/plugin install mobile-cicd@goodiny777-skills

# or as a plain skill
git clone https://github.com/goodiny777/mobile-cicd-skill
cp -r mobile-cicd-skill/skills/mobile-cicd ~/.claude/skills/        # personal
cp -r mobile-cicd-skill/skills/mobile-cicd .claude/skills/          # project
```

Then in any mobile repo: *"set up CI/CD for this app"* or `/mobile-cicd`.

### Claude.ai / Claude Desktop (Cowork)

The chat app has no public catalogue — skills are uploaded per account (or by an org admin for a workspace):

1. Download [`dist/mobile-cicd.skill`](dist/mobile-cicd.skill) (also attached to every [release](https://github.com/goodiny777/mobile-cicd-skill/releases)).
2. Claude → Settings → Capabilities → Skills → **Upload skill** → pick the file.
3. In a Cowork task with your repo folder connected: *"set up release CI/CD for this app"*.

`dist/mobile-cicd.skill` is a zip of `skills/mobile-cicd/` produced by Anthropic's `package_skill.py`; rebuild it after editing the skill (see *Releasing* below).

### OpenAI Codex CLI

Codex reads the same format from `.agents/skills/` (repo) or `~/.agents/skills/` (user):

```bash
git clone https://github.com/goodiny777/mobile-cicd-skill
mkdir -p ~/.agents/skills && cp -r mobile-cicd-skill/skills/mobile-cicd ~/.agents/skills/
```

Invoke with `$mobile-cicd` in the TUI or `codex exec "$mobile-cicd set up release CI for this repo"`.

### Google Gemini CLI

```bash
git clone https://github.com/goodiny777/mobile-cicd-skill
mkdir -p ~/.gemini/skills && cp -r mobile-cicd-skill/skills/mobile-cicd ~/.gemini/skills/
```

Project-scoped: `.gemini/skills/mobile-cicd/`. Gemini activates it from the description; you can also say *"use the mobile-cicd skill"*.

### Cursor

Project-scoped only:

```bash
mkdir -p .cursor/skills && cp -r mobile-cicd-skill/skills/mobile-cicd .cursor/skills/
```

### Cross-agent installers

If you use a skills CLI (e.g. `npx skills add goodiny777/mobile-cicd-skill`, or `localskills install`), point it at this repository — the layout follows the Agent Skills standard (`skills/<name>/SKILL.md`).

### Any other LLM (ChatGPT, Gemini web, local models)

The skill is plain markdown and bash, so it works without an agent runtime — you just do the file operations yourself:

1. Paste `skills/mobile-cicd/SKILL.md` as the system prompt (or first message).
2. Run `scripts/detect_project.sh .` in your repo and paste the output.
3. When the model asks for a reference (`references/troubleshooting.md`, `references/xcode-cloud-console.md`, …), paste that file.
4. Copy the generated files from `assets/` and apply the edits it proposes; run `scripts/check_ci_scripts.sh .` before tagging.

You lose the automatic push-watch-fix loop, but keep the interview, the templates, the console table and the failure catalogue — which is most of the value.

---

## Repository layout

```
skills/mobile-cicd/
├── SKILL.md                         # the workflow (six phases)
├── references/
│   ├── platform-notes.md            # Windows / macOS / Linux differences, what needs a Mac
│   ├── interview.md                 # question bank, trigger blocks, secret-storage options
│   ├── runbook.md                   # universal runbook to copy into the project
│   ├── xcode-cloud-console.md       # every console setting, with the reason
│   ├── console-chrome-flow.md       # driving App Store Connect with Chrome, safely
│   ├── github-actions-play.md       # Play service account, upload, versionCode
│   ├── firebase-app-distribution.md # Android (Actions) and iOS (Xcode Cloud ad-hoc)
│   └── troubleshooting.md           # F-1 … F-20, from real runs
├── assets/
│   ├── xcode-cloud/{flutter,native,react-native,common}/  # ci_post_clone / ci_pre_xcodebuild / ci_post_xcodebuild / notify.sh
│   ├── github-actions/              # release-android-flutter.yml, release-android-gradle.yml, notify.sh
│   └── gitattributes-snippet
└── scripts/
    ├── detect_project.sh            # read-only project report
    ├── check_ci_scripts.sh          # pre-push harness (exit 1 on FAIL)
    ├── fix_exec_bits.sh / .ps1      # set 100755 in the git index, any OS
    └── watch_github_run.sh          # gh run watch + focused failure log
docs/mobile-cicd-runbook.md          # the runbook, standalone
dist/mobile-cicd.skill               # packaged skill for Claude.ai / Claude Desktop upload
.claude-plugin/                      # Claude Code plugin + marketplace manifests
```

---

## Design rules the skill enforces

- **Fail before you pay.** Tag ↔ version mismatch and missing required keys fail in the first seconds of `ci_post_clone.sh`, not after a 10-minute archive.
- **Secrets by name only.** The agent never needs a value; the pipelines log `KEY present (N chars) — value not logged`; keystores are decoded to a file and scrubbed in an `if: always()` step; Xcode Cloud variables are marked *Keep value redacted*.
- **Honest notifications.** iOS reports `ARCHIVED`, never `DEPLOYED`, because TestFlight delivery happens after the script; the email post-action is the backstop.
- **Per-platform triggers.** `ios/v*` and `android/v*`; a bare `v*` is a deliberate no-op so old habits fail silently and free.
- **No macOS runners.** Linux for Android, Xcode Cloud for iOS. If a macOS job survives, the harness warns.
- **Measure, don't estimate.** The runbook records billed minutes from the first green build and recomputes headroom.
- **Git-index truth.** `ci_scripts/*.sh` must be `100755` and LF *in the index* — the single most common reason Apple silently ignores them, invisible on Windows.

---

## Requirements

- **Works from Windows, macOS and Linux.** The helper scripts are bash: on Windows they run under Git Bash (bundled with Git for Windows), which Claude Code uses by default; a PowerShell twin is provided where PowerShell behaves differently (`scripts/fix_exec_bits.ps1`). `skills/mobile-cicd/references/platform-notes.md` lists the OS-specific traps and which steps need a Mac (only the first-time Xcode Cloud workflow creation and CocoaPods/SPM lock regeneration).
- The agent needs a shell, file tools and (for the push/watch loop) an authenticated `gh` CLI and `jq`.
- Apple: an App Store Connect account with Admin/App Manager, the app record created, and a Mac with Xcode **once** to create the first Xcode Cloud workflow (later edits are web-only).
- Google: Play Console admin to create the service account; a first manual AAB upload before API uploads work.
- Optional: the Claude in Chrome extension for hands-off console configuration.

---

## Where it's listed

| Channel | How to get it |
|---|---|
| This repo as a Claude Code marketplace | `/plugin marketplace add goodiny777/mobile-cicd-skill` → `/plugin install mobile-cicd@goodiny777-skills` |
| Anthropic's official plugin directory (`/plugin → Discover`) | submitted via Anthropic's [plugin directory form](https://clau.de/plugin-directory-submission); once approved: `/plugin install mobile-cicd@claude-plugins-official` |
| Claude.ai / Desktop | upload `dist/mobile-cicd.skill` (Settings → Capabilities → Skills) |
| Codex / Gemini CLI / Cursor | copy `skills/mobile-cicd/` into the agent's skills directory (see *Install*) |
| Cross-agent registries (skills.sh, agensi.io, localskills.sh, …) | they index public repos with the `skills/<name>/SKILL.md` layout; nothing extra to do |

## Releasing

```bash
# 1. bump version in skills/mobile-cicd/SKILL.md (metadata.version), .claude-plugin/plugin.json, marketplace.json, CHANGELOG.md
# 2. rebuild the packaged skill (needs Anthropic's skill-creator scripts, or any zip of skills/mobile-cicd/)
python -m scripts.package_skill skills/mobile-cicd dist/
# 3. tag and publish with the .skill attached
git commit -am "release: vX.Y.Z" && git tag vX.Y.Z && git push --tags
gh release create vX.Y.Z --title "mobile-cicd X.Y.Z" --notes-file CHANGELOG.md dist/mobile-cicd.skill
```

## Contributing

Issues and PRs welcome — especially new entries for `references/troubleshooting.md` with the *real* cause, not the message. Keep the rules above; run `shellcheck -x` on any script; never add a value that looks like a key, even a fake one.

## License

MIT © Mikhail Babozhko
