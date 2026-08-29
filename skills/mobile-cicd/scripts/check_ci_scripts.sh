#!/bin/bash
# check_ci_scripts.sh — pre-push harness for Xcode Cloud ci_scripts and the Android workflow.
# Usage: scripts/check_ci_scripts.sh [repo-root]
# Exit 1 on any FAIL. WARNs don't fail.
#
# Checks (each one corresponds to a real first-run failure — see references/troubleshooting.md):
#   1. every ci_scripts/*.sh is 100755 in the git INDEX            (F-3)
#   2. no CRLF in the committed content                            (F-3)
#   3. bash -n parses; shellcheck if installed
#   4. notify.sh sits beside the scripts (they source it)
#   5. a shared scheme with an Archive action exists               (console §A)
#   6. .gitattributes forces LF for *.sh
#   7. no macOS runner left in .github/workflows                    (cost)
#   8. no key-shaped strings committed under ci_scripts/ or .github/ (F-19)
#   9. no keystore / key.properties / .env tracked

set -uo pipefail
ROOT="$(cd "${1:-.}" && pwd)"
cd "$ROOT" || exit 1
FAILS=0; WARNS=0
pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILS=$((FAILS+1)); }
warn() { echo "  WARN  $*"; WARNS=$((WARNS+1)); }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $ROOT"; exit 1; }

DIRS="$(find . -type d -name ci_scripts -not -path '*/node_modules/*' -not -path '*/Pods/*' -not -path '*/.git/*' | sed 's#^\./##')"
[ -n "$DIRS" ] || { fail "no ci_scripts/ directory found"; }

for d in $DIRS; do
  echo "== $d"
  for f in "$d"/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    mode="$(git ls-files -s -- "$f" | awk '{print $1}')"
    if [ -z "$mode" ]; then fail "$name is not tracked by git (git add it)"
    elif [ "$mode" = "100755" ]; then pass "$name index mode 100755"
    else fail "$name index mode is $mode — run: git update-index --chmod=+x $f"; fi

    if [ -n "$mode" ]; then
      if git show ":$f" | grep -q $'\r'; then fail "$name has CRLF line endings in the index (set *.sh text eol=lf, re-add)"; else pass "$name LF endings"; fi
      if git show ":$f" | head -1 | grep -qE '^#!/bin/(ba)?sh'; then pass "$name shebang"; else fail "$name missing #!/bin/bash shebang"; fi
    fi
    if bash -n "$f" 2>/dev/null; then pass "$name bash -n"; else fail "$name does not parse (bash -n)"; fi
    if command -v shellcheck >/dev/null 2>&1; then
      if shellcheck -x -S warning "$f" >/dev/null 2>&1; then pass "$name shellcheck"; else warn "$name shellcheck warnings: shellcheck -x $f"; fi
    fi
  done
  if grep -lq 'notify.sh' "$d"/ci_*.sh 2>/dev/null; then
    [ -f "$d/notify.sh" ] && pass "notify.sh present beside scripts" || fail "scripts source notify.sh but $d/notify.sh is missing"
  fi
  if grep -qE '^\s*pod install' "$d/ci_post_clone.sh" 2>/dev/null && grep -q 'flutter build ios --config-only' "$d/ci_post_clone.sh" 2>/dev/null; then
    warn "ci_post_clone.sh runs pod install AND flutter build --config-only (which already runs it) — F-9"
  fi
done

echo "== scheme"
found_scheme=0
while IFS= read -r s; do
  [ -f "$s" ] || continue
  found_scheme=1
  if grep -q '<ArchiveAction' "$s"; then
    cfg="$(grep -A2 '<ArchiveAction' "$s" | sed -n 's/.*buildConfiguration = "\([^"]*\)".*/\1/p' | head -1)"
    [ "$cfg" = "Release" ] && pass "shared scheme $(basename "$s" .xcscheme) archives Release" || warn "shared scheme $(basename "$s" .xcscheme) archive config is '$cfg'"
  else
    warn "shared scheme $(basename "$s" .xcscheme) has no ArchiveAction"
  fi
done < <(find . -path '*/xcshareddata/xcschemes/*.xcscheme' -not -path '*/Pods/*' -not -path '*/node_modules/*' 2>/dev/null)
[ "$found_scheme" -eq 1 ] || fail "no shared .xcscheme found — Xcode Cloud requires a shared scheme"

echo "== git attributes"
if [ -f .gitattributes ] && grep -qE '^\*\.sh\s+text\s+eol=lf' .gitattributes; then pass ".gitattributes forces LF for *.sh"; else warn "add '*.sh text eol=lf' to .gitattributes"; fi

echo "== github workflows"
if [ -d .github/workflows ]; then
  if grep -lE 'runs-on:.*macos' .github/workflows/*.y*ml >/dev/null 2>&1; then
    warn "macOS runner still present: $(grep -lE 'runs-on:.*macos' .github/workflows/*.y*ml | tr '\n' ' ') — 10× minutes; rollback path or leak?"
  else pass "no macOS runners in .github/workflows"; fi
  if grep -lE "tags:.*'v\*'|tags:\s*\[\s*'v\*'" .github/workflows/*.y*ml >/dev/null 2>&1; then
    warn "a workflow still triggers on bare v* tags — the split scheme expects android/v* only"
  fi
fi

echo "== secrets hygiene"
PATTERNS='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[0-9]{8,10}:[A-Za-z0-9_-]{35}|"private_key_id"|[a-f0-9]{32}'
hits="$(git grep -nE "$PATTERNS" -- ':(glob)**/ci_scripts/*' ':(glob).github/**' 2>/dev/null | grep -v 'check_ci_scripts' || true)"
[ -z "$hits" ] && pass "no key-shaped strings under ci_scripts/ or .github/" || { fail "possible secret committed:"; echo "$hits" | sed 's/^/        /'; }
tracked="$(git ls-files | grep -Ei '(\.jks|\.keystore|key\.properties|^\.env$|/\.env$|\.p12$|\.mobileprovision$|\.p8$)' || true)"
[ -z "$tracked" ] && pass "no keystore/.env/cert files tracked" || { fail "sensitive files tracked in git:"; echo "$tracked" | sed 's/^/        /'; }

echo
echo "FAIL=$FAILS WARN=$WARNS"
[ "$FAILS" -eq 0 ] && { echo "ready to tag"; exit 0; } || { echo "fix FAILs before pushing a release tag"; exit 1; }
