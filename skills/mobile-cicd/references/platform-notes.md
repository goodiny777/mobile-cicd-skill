# Platform notes — running this skill from Windows, macOS, or Linux

Read this once at the start of Phase 0, after you know which OS the agent's shell is on (`uname -s` in bash → `Darwin` / `Linux` / `MINGW64_NT…` for Git Bash; or `$PSVersionTable` in PowerShell). Everything the skill generates runs on Apple's or GitHub's machines, so the **output** is OS-independent. What differs is how you drive git and the helper scripts locally, and which tasks need a Mac at all.

## 1. Shell: everything in `scripts/` is bash

| OS | How to run `scripts/*.sh` | Notes |
|---|---|---|
| macOS / Linux | `bash scripts/detect_project.sh .` | zsh is fine as the outer shell; the scripts declare `#!/bin/bash` |
| Windows, Git Bash (ships with Git for Windows) | `bash scripts/detect_project.sh .` | Claude Code on Windows uses Git Bash by default — this just works |
| Windows, PowerShell only | `& "C:\Program Files\Git\bin\bash.exe" scripts/detect_project.sh .` | or use the `.ps1` twins where provided (`fix_exec_bits.ps1`) |

If `bash` is missing entirely on Windows, install Git for Windows first; the skill's scripts are not worth porting to PowerShell one by one.

## 2. PowerShell traps (each one has cost a real user an hour)

| Trap | Symptom | Do this instead |
|---|---|---|
| `&&` is not a separator in Windows PowerShell 5 | `The token '&&' is not a valid statement separator` | use `;` or separate lines (PowerShell 7 accepts `&&`) |
| Globs are **not expanded** for external commands | `git update-index --chmod=+x dir/*.sh` silently does nothing → scripts stay `100644` → Apple ignores them (F-3) | `scripts/fix_exec_bits.ps1`, or `bash scripts/fix_exec_bits.sh` |
| `core.filemode=false` on Windows | the on-disk executable bit means nothing; only the index bit is real | always verify with `git ls-files -s \| Select-String 100755` |
| `core.autocrlf=true` default | CRLF sneaks into `.sh` → shebang breaks on macOS | `.gitattributes` with `*.sh text eol=lf` (the skill's snippet) and `git add --renormalize .` after adding it |
| Em-dashes / non-ASCII in `gh --description` | command fails or truncates in some terminals | keep `--description` ASCII |
| `base64 -w0` doesn't exist | keystore encoding for the GitHub secret | `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) \| Set-Clipboard` |
| `Set-Clipboard` vs `clip` | either works; `clip` adds a trailing newline in some versions | prefer `Set-Clipboard` |

## 3. macOS traps

| Trap | Do this instead |
|---|---|
| `base64 -w0` is GNU-only | `base64 -i upload-keystore.jks \| tr -d '\n' \| pbcopy` |
| `sed -i` needs an argument (`sed -i ''`) | the skill's scripts never use `sed -i`; if you write one, use `sed -i ''` or a python one-liner |
| `stat -c%s` is GNU | on a Mac use `stat -f%z`; the workflow templates run on Ubuntu so they keep `-c` |
| `find -regextype` unsupported | the scripts use `-path`/`-name` only |
| Homebrew CocoaPods vs system Ruby | same `require 'xcodeproj'` issue as on Apple's CI image (F-7) — `gem install --user-install xcodeproj` |

## 4. Base64 for the keystore secret — one line per OS

```bash
# Linux
base64 -w0 upload-keystore.jks | xclip -selection clipboard
# macOS
base64 -i upload-keystore.jks | tr -d '\n' | pbcopy
# Windows Git Bash
base64 -w0 upload-keystore.jks | clip
```
```powershell
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

Then paste into the GitHub secret `ANDROID_KEYSTORE_BASE64` — never into chat.

## 5. Tasks that need a Mac, and what to do from Windows/Linux

| Task | Why Mac-only | From Windows/Linux |
|---|---|---|
| Creating the Xcode Cloud workflow the first time | Apple requires it from inside Xcode | Ask the owner (or any teammate with Xcode) to do it once; everything after is web-editable — the skill's console table applies from any OS |
| Regenerating `ios/Podfile.lock` | needs CocoaPods + Xcode toolchain | Ship with the `DELETE_STALE_PODFILE_LOCK=true` workaround and put "regenerate on a Mac" in runbook §7 as an open item |
| Committing `Package.resolved` for SPM | Xcode resolves it | Use CocoaPods until a Mac is available (F-5) |
| Local `flutter build ipa` / `xcodebuild archive` smoke test | toolchain | Skip; the first Xcode Cloud run *is* the smoke test — budget the 3–8 fix commits |
| Registering test devices, exporting certificates | Apple tooling / Keychain | Not needed with managed signing; UDIDs can be added in the developer portal from any browser |

Everything else — detection, interview, secrets map, generating `ci_scripts` and workflows, the harness, console configuration via web/Chrome, pushing tags, watching runs, reading Xcode Cloud logs in the browser — works identically on all three OSes.

## 6. Tool availability check (run once)

```bash
for t in git gh jq bash shellcheck; do printf '%-11s %s\n' "$t" "$(command -v $t >/dev/null && echo ok || echo MISSING)"; done
gh auth status
```

`shellcheck` is optional (the harness skips it when absent). `gh` and `jq` are needed only for the push-watch-fix loop; install with `winget install GitHub.cli jqlang.jq` / `brew install gh jq` / `apt install gh jq`.
