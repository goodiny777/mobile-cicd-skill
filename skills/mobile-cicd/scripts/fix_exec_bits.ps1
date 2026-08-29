# fix_exec_bits.ps1 — PowerShell twin of fix_exec_bits.sh.
# Marks every ci_scripts/*.sh, .github/scripts/*.sh and scripts/*.sh executable in the git index.
# Why a separate file: PowerShell does not expand globs for external commands, so
#   git update-index --chmod=+x ios/ci_scripts/*.sh
# silently does nothing. This script enumerates the files itself.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/fix_exec_bits.ps1 [repo-root]

param([string]$Root = ".")
Set-Location $Root
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "not a git repo: $Root"; exit 1 }

$base = (Get-Location).Path
$files = Get-ChildItem -Recurse -Filter *.sh -File |
  Where-Object { $_.FullName -match '[\\/](ci_scripts|\.github[\\/]scripts|scripts)[\\/][^\\/]+\.sh$' -and $_.FullName -notmatch '[\\/](node_modules|Pods|\.git)[\\/]' } |
  ForEach-Object { $_.FullName.Substring($base.Length + 1) -replace '\\', '/' }

$n = 0
foreach ($f in $files) {
  git add -- $f 2>$null
  git update-index --chmod=+x -- $f
  if ($LASTEXITCODE -eq 0) { $n++ }
}
Write-Host "marked $n script(s) 100755 in the index"
git ls-files -s | Select-String '^100755' | ForEach-Object { "  " + ($_ -split "`t")[1] }
if ($n -gt 0) { Write-Host "now commit: git commit -m 'chore: mark CI scripts executable'" }
