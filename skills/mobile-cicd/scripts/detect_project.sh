#!/bin/bash
# detect_project.sh — print what the mobile-cicd skill needs to know about a repo.
# Usage: scripts/detect_project.sh [repo-root]   (default: .)
# Read-only. Works on Linux/macOS/Git-Bash. Never prints secret values.

set -uo pipefail
ROOT="$(cd "${1:-.}" && pwd)"
cd "$ROOT" || exit 1

say()  { printf '%-30s %s\n' "$1" "$2"; }
head_() { echo; echo "## $1"; }

# ---------------------------------------------------------------------------
head_ "repo"
say "root" "$ROOT"
say "git remote" "$(git remote get-url origin 2>/dev/null || echo none)"
say "default branch" "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#origin/##' || echo '?')"
if [ -f .gitmodules ]; then
  say "submodules" "$(git config -f .gitmodules --get-regexp 'submodule\..*\.path' | awk '{print $2}' | tr '\n' ' ')"
else
  say "submodules" "none"
fi

# ---------------------------------------------------------------------------
head_ "stack"
IOS_DIR=""; ANDROID_DIR=""; STACK="unknown"
if [ -f pubspec.yaml ]; then
  STACK="flutter"; [ -d ios ] && IOS_DIR="ios"; [ -d android ] && ANDROID_DIR="android"
elif [ -f package.json ] && grep -q '"react-native"' package.json 2>/dev/null; then
  STACK="react-native"; [ -d ios ] && IOS_DIR="ios"; [ -d android ] && ANDROID_DIR="android"
elif [ -d iosApp ] && ls shared/build.gradle* >/dev/null 2>&1; then
  STACK="kmp"; IOS_DIR="iosApp"; [ -d androidApp ] && ANDROID_DIR="androidApp"
else
  xp="$(find . -maxdepth 3 -name '*.xcodeproj' -not -path '*/node_modules/*' -not -path '*/Pods/*' -not -path '*/.git/*' | head -1)"
  [ -n "$xp" ] && IOS_DIR="$(dirname "$xp" | sed 's#^\./##')"
  gr="$(find . -maxdepth 3 \( -name 'build.gradle' -o -name 'build.gradle.kts' \) -path '*/app/*' -not -path '*/node_modules/*' | head -1)"
  [ -n "$gr" ] && ANDROID_DIR="$(dirname "$(dirname "$gr")" | sed 's#^\./##')"
  if [ -n "$IOS_DIR" ] && [ -n "$ANDROID_DIR" ]; then STACK="multi (native iOS + native Android)"
  elif [ -n "$IOS_DIR" ]; then STACK="native-ios"
  elif [ -n "$ANDROID_DIR" ]; then STACK="native-android"; fi
fi
say "stack" "$STACK"
say "ios module" "${IOS_DIR:-none}"
say "android module" "${ANDROID_DIR:-none}"
[ -n "$IOS_DIR" ] && [ -n "$ANDROID_DIR" ] && say "ASK" "both modules present — which platform(s) to deploy?"

# ---------------------------------------------------------------------------
if [ -n "$IOS_DIR" ]; then
  head_ "ios"
  WS="$(ls -d "$IOS_DIR"/*.xcworkspace 2>/dev/null | head -1)"
  PJ="$(ls -d "$IOS_DIR"/*.xcodeproj 2>/dev/null | head -1)"
  say "workspace" "${WS:-none}"
  say "xcodeproj" "${PJ:-none}"
  if [ -n "$PJ" ]; then
    SCHEMES="$(ls "$PJ/xcshareddata/xcschemes/" 2>/dev/null | sed 's/\.xcscheme$//' | tr '\n' ' ')"
    say "shared schemes" "${SCHEMES:-NONE (Xcode Cloud needs a shared scheme)}"
    for s in "$PJ"/xcshareddata/xcschemes/*.xcscheme; do
      [ -f "$s" ] || continue
      cfg="$(grep -A2 '<ArchiveAction' "$s" | sed -n 's/.*buildConfiguration = "\([^"]*\)".*/\1/p' | head -1)"
      say "  archive config ($(basename "$s" .xcscheme))" "${cfg:-missing}"
    done
    auto="$(grep -c 'CODE_SIGN_STYLE = Automatic' "$PJ/project.pbxproj" 2>/dev/null || true)"
    manual="$(grep -c 'CODE_SIGN_STYLE = Manual' "$PJ/project.pbxproj" 2>/dev/null || true)"
    team="$(grep -m1 'DEVELOPMENT_TEAM = ' "$PJ/project.pbxproj" 2>/dev/null | sed 's/.*= *\([A-Z0-9]*\);.*/\1/')"
    say "signing" "automatic=$auto manual=$manual DEVELOPMENT_TEAM=$([ -n "$team" ] && echo set || echo MISSING)"
    bid="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER = ' "$PJ/project.pbxproj" 2>/dev/null | sed 's/.*= *\([^;]*\);.*/\1/')"
    say "bundle id" "${bid:-?}"
    mv_="$(grep -m1 'MARKETING_VERSION = ' "$PJ/project.pbxproj" 2>/dev/null | sed 's/.*= *\([0-9.]*\);.*/\1/')"
    [ -n "$mv_" ] && say "MARKETING_VERSION" "$mv_"
    targets="$(grep -c 'isa = PBXNativeTarget' "$PJ/project.pbxproj" 2>/dev/null || true)"
    say "native targets" "$targets (extensions/widgets each need DEVELOPMENT_TEAM)"
  fi
  [ -f "$IOS_DIR/Podfile" ] && say "cocoapods" "Podfile present"
  if [ -f "$IOS_DIR/Podfile.lock" ]; then
    last="$(git log -1 --format=%ct -- "$IOS_DIR/Podfile.lock" 2>/dev/null || echo "$(date +%s)")"
    age_days=$(( ( $(date +%s) - last ) / 86400 ))
    say "Podfile.lock age" "${age_days} days since last commit$( [ "$age_days" -gt 60 ] && echo '  ← STALE, regenerate on a Mac (F-8)' )"
  fi
  spm="$(find "$IOS_DIR" -maxdepth 5 -name Package.resolved -not -path '*/Pods/*' 2>/dev/null | head -1)"
  say "SPM Package.resolved" "${spm:-none (needed, committed, if SPM is used — F-5)}"
  if [ -d "$IOS_DIR/ci_scripts" ]; then
    say "ci_scripts" "$(ls "$IOS_DIR/ci_scripts" | tr '\n' ' ')"
    for f in "$IOS_DIR"/ci_scripts/*.sh; do
      [ -f "$f" ] || continue
      mode="$(git ls-files -s -- "$f" 2>/dev/null | awk '{print $1}')"
      crlf="$(git show ":$f" 2>/dev/null | grep -c $'\r' || true)"
      say "  $(basename "$f")" "index-mode=${mode:-untracked} crlf-lines=$crlf"
    done
  else
    say "ci_scripts" "none"
  fi
fi

# ---------------------------------------------------------------------------
if [ -n "$ANDROID_DIR" ]; then
  head_ "android (gradle)"
  APP_GRADLE=""
  for c in "$ANDROID_DIR/app/build.gradle.kts" "$ANDROID_DIR/app/build.gradle"; do [ -f "$c" ] && { APP_GRADLE="$c"; break; }; done
  say "app module gradle" "${APP_GRADLE:-not found}"
  if [ -f "$ANDROID_DIR/settings.gradle.kts" ] || [ -f "$ANDROID_DIR/settings.gradle" ]; then
    mods="$(cat "$ANDROID_DIR"/settings.gradle* 2>/dev/null | grep -oE 'include *\(?[^)]*' | grep -oE '":?[A-Za-z0-9_:-]+"' | tr -d '"' | tr '\n' ' ')"
    say "gradle modules" "${mods:-?}"
  fi
  if [ -n "$APP_GRADLE" ]; then
    pkg="$(grep -m1 -E 'applicationId *=? *"' "$APP_GRADLE" | sed -E 's/.*"([^"]+)".*/\1/')"
    say "applicationId" "${pkg:-? (maybe in a variable)}"
    say "namespace" "$(grep -m1 -E 'namespace *=? *"' "$APP_GRADLE" | sed -E 's/.*"([^"]+)".*/\1/')"
    vc="$(grep -m1 -E 'versionCode' "$APP_GRADLE" | sed 's/^[[:space:]]*//' | cut -c1-70)"
    vn="$(grep -m1 -E 'versionName' "$APP_GRADLE" | sed 's/^[[:space:]]*//' | cut -c1-70)"
    say "versionCode line" "${vc:-?}"
    say "versionName line" "${vn:-?}"
    echo "$vc$vn" | grep -qE 'findProperty|project\.(property|hasProperty)|flutter\.version' && say "  version wiring" "reads from properties/Flutter — CI can pass -P or --build-number" || say "  version wiring" "HARD-CODED? — wire -PversionCode/-PversionName (see gradle template header)"
    flavors="$(sed -n '/productFlavors/,/^\s*}/p' "$APP_GRADLE" | grep -oE '^\s*(create\(")?[a-zA-Z0-9_]+("\))?\s*\{' | grep -vE 'productFlavors|create' | tr -d '{" ' | tr '\n' ' ')"
    say "product flavors" "${flavors:-none}"
    if grep -q 'signingConfigs' "$APP_GRADLE"; then
      src="$(sed -n '/signingConfigs/,/^\s*}/p' "$APP_GRADLE" | grep -oE 'key\.properties|keystoreProperties|System\.getenv|project\.property|findProperty|storeFile' | sort -u | tr '\n' ' ')"
      say "signingConfigs" "present — reads via: ${src:-?}"
      grep -qE 'storePassword *=? *"[^"$]' "$APP_GRADLE" && say "  WARNING" "a password literal may be hard-coded in $APP_GRADLE"
    else
      say "signingConfigs" "NONE — release build will be unsigned; add key.properties wiring"
    fi
    grep -qE 'minifyEnabled *=? *true|isMinifyEnabled *= *true' "$APP_GRADLE" && say "minify" "on (upload mapping.txt to Play)" || say "minify" "off"
  fi
  [ -f "$ANDROID_DIR/key.properties" ] && say "WARNING" "$ANDROID_DIR/key.properties exists in the working tree — must be gitignored"
  git ls-files "$ANDROID_DIR" | grep -Ei '\.(jks|keystore)$|key\.properties$' | while read -r k; do say "WARNING" "tracked in git: $k"; done
  say "gradle wrapper" "$( [ -f "$ANDROID_DIR/gradlew" ] && grep -oE 'gradle-[0-9.]+' "$ANDROID_DIR/gradle/wrapper/gradle-wrapper.properties" 2>/dev/null | head -1 || echo missing )"
  say "google-services.json" "$( find "$ANDROID_DIR" -maxdepth 3 -name google-services.json | head -1 || echo none )"
fi

# ---------------------------------------------------------------------------
head_ "versions"
[ -f pubspec.yaml ] && say "pubspec version" "$(sed -n 's/^version:[[:space:]]*\(.*\)/\1/p' pubspec.yaml | head -1)"
[ -f pubspec.yaml ] && say "dart sdk constraint" "$(sed -n 's/^[[:space:]]*sdk:[[:space:]]*\(.*\)/\1/p' pubspec.yaml | head -1)"
[ -f .fvmrc ] && say "fvm flutter" "$(sed -n 's/.*"flutter":[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc)"
[ -f package.json ] && say "package.json version" "$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -1)"
[ -f .nvmrc ] && say "nvmrc" "$(cat .nvmrc)"
[ -f gradle.properties ] && grep -E '^version(Name|Code)=' gradle.properties | while read -r l; do say "gradle.properties" "$l"; done

# ---------------------------------------------------------------------------
head_ "existing CI"
if [ -d .github/workflows ]; then
  for w in .github/workflows/*.y*ml; do
    [ -f "$w" ] || continue
    trig="$(awk '/^on:/{f=1} f&&NR<40' "$w" | head -6 | tr -d '\n' | tr -s ' ' | cut -c1-90)"
    mac="$(grep -c 'macos' "$w" || true)"
    say "$(basename "$w")" "macos-refs=$mac ${trig}"
  done
else
  say "github workflows" "none"
fi
[ -f fastlane/Fastfile ] && say "fastlane" "Fastfile present (lanes: $(grep -oE 'lane :[a-z_]+' fastlane/Fastfile | sed 's/lane ://' | tr '\n' ' '))"
[ -f codemagic.yaml ] && say "codemagic" "codemagic.yaml present"
[ -f bitrise.yml ] && say "bitrise" "bitrise.yml present"
[ -f firebase.json ] && say "firebase" "firebase.json present"

# ---------------------------------------------------------------------------
head_ "tags"
say "recent tags" "$(git tag --sort=-creatordate 2>/dev/null | head -6 | tr '\n' ' ')"
say "tag prefixes seen" "$(git tag 2>/dev/null | sed -n 's#^\([a-z]*\)/v.*#\1/#p' | sort -u | tr '\n' ' ')"
say "gh cli" "$(command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && echo 'authenticated' || echo 'missing or not logged in — needed for gh secret list / run watch')"
