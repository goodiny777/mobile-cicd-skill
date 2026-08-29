#!/bin/bash
# fix_exec_bits.sh — mark every ci_scripts/*.sh (and .github/scripts/*.sh) executable IN THE GIT INDEX.
# Works on Linux, macOS and Windows Git Bash. On Windows core.filemode=false, so the on-disk bit
# is meaningless — only the index bit reaches GitHub and Xcode Cloud (troubleshooting F-3).
#
# Usage: scripts/fix_exec_bits.sh [repo-root]
# PowerShell users without Git Bash: see scripts/fix_exec_bits.ps1

set -uo pipefail
ROOT="$(cd "${1:-.}" && pwd)"
cd "$ROOT" || exit 1
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo: $ROOT"; exit 1; }

n=0
while IFS= read -r f; do
  git add -- "$f" 2>/dev/null
  git update-index --chmod=+x -- "$f" && n=$((n+1))
done < <(git ls-files -co --exclude-standard | grep -E '(^|/)(ci_scripts|\.github/scripts|scripts)/[^/]+\.sh$')

echo "marked $n script(s) 100755 in the index"
git ls-files -s | awk '$1=="100755"{print "  "$4}'
[ "$n" -gt 0 ] && echo "now commit: git commit -m 'chore: mark CI scripts executable'"
exit 0
