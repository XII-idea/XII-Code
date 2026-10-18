#requires -Version 5.1
<#
.release.ps1 - record a successful build into VERSIONS.md and (best-effort)
attach the dist artifacts to a draft GitHub Release.

VERSIONS.md is the repo-side source of truth for "last good pin + commit",
used by the failure-rollback policy in AGENTS.md 搂7.5.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('stable','insider')][string]$Channel,
  [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$Versions  = Join-Path $RepoRoot 'VERSIONS.md'
$VscodeDir = Join-Path $RepoRoot 'vscode'
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) { $gitCmd = 'git' }
$commit = ''
if (Test-Path (Join-Path $VscodeDir '.git/HEAD')) {
  $commit = & $gitCmd -C $VscodeDir rev-parse HEAD 2>$null
  if ($LASTEXITCODE -ne 0) { $commit = 'unknown' }
}

# electron pin (if present)
$pin = ''
$pinFile = Join-Path $RepoRoot 'overlay/electron-pin.txt'
if (Test-Path $pinFile) {
  $pin = (Get-Content $pinFile | Where-Object { $_ -match '^target=' }) -replace 'target=', '' -replace '"', ''
}

$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
$artifact = if ($Channel -eq 'stable') { "XII Code Setup $Version.exe" } else { "XII Code Insiders Setup $Version.exe" }

if (-not (Test-Path $Versions)) {
  @"
# Version history

Each successful build appends one row. Used for pin rollback (AGENTS.md 搂7.5).

| Time (UTC) | Channel | Upstream commit | Electron pin | Artifact |
|---|---|---|---|---|
"@ | Set-Content $Versions -Encoding UTF8
}
$line = "| $ts | $Channel | $commit | $pin | $artifact |"
Add-Content $Versions $line -Encoding UTF8
Write-Host "recorded $line"

# best-effort draft release attach (only when GITHUB_TOKEN is available in CI)
if ($env:GITHUB_TOKEN) {
  $repoSlug = & $gitCmd remote get-url origin 2>$null
  if ($LASTEXITCODE -eq 0 -and $repoSlug -match 'github\.com[/:]([^/]+/[^/]+?)(\.git)?$') {
    $slug = $Matches[1]
    $distDir = Join-Path $RepoRoot "dist/$Channel"
    if (Test-Path $distDir) {
      $tag = "xii-$($Channel.ToLower())-$Version"
      & $gitCmd tag "$tag" 2>$null
      Write-Host "draft release tag ready: $tag (attach manually or via gh release)"
    }
  }
} else {
  Write-Warning "no GITHUB_TOKEN; skipped release attach"
}


