#requires -Version 5.1
<#
.cleanup.ps1 - expire XII Code artifacts / draft releases older than a retention window.

Default 8h. Operates on:
  - draft GitHub Releases tagged xii-<channel>-<version> whose PUBLISHED/upload
    time is older than RetentionHours -> delete their assets (keep the changelog
    tag if present, drop the assets).
  - local dist/ older than retention -> remove.

Called by ci.yml on every scheduled run. No-op when there is nothing to do.
Requires the git CLI on PATH and, for the release part, GITHUB_TOKEN + gh.
#>

[CmdletBinding()]
param(
  [Parameter()][int]$RetentionHours = 8
)

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }

$RepoRoot = Split-Path -Parent $PSScriptRoot
$now = (Get-Date).ToUniversalTime()
$threshold = $now.AddHours(-$RetentionHours)
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) { $gitCmd = 'git' }
$git = $gitCmd
$removed = 0

# ---- 1. local dist/ older than retention -------------------------------
$dist = Join-Path $RepoRoot 'dist'
if (Test-Path $dist) {
  Get-ChildItem $dist -Directory | ForEach-Object {
    if ($_.LastWriteTimeUtc -lt $threshold) {
      Write-Host "removing local $($_.Name)"
      Remove-Item $_.FullName -Recurse -Force
      $removed++
    }
  }
}

# ---- 2. draft releases older than retention (best-effort) ---------------
if ($env:GITHUB_TOKEN) {
  $slug = & $git remote get-url origin 2>$null
  if ($LASTEXITCODE -eq 0 -and $slug -match 'github\.com[/:]([^/]+/[^/]+?)(\.git)?$') {
    $repo = $Matches[1]
    $releases = & gh release list -R $repo --json tagName,isDraft,publishedAt,assets 2>$null
    if ($LASTEXITCODE -eq 0 -and $releases) {
      $rels = $releases | ConvertFrom-Json
      foreach ($r in $rels) {
        if (-not $r.isDraft) { continue }          # only draft
        $t = $r.publishedAt
        if ($t -and ([datetime]$t -lt $threshold)) {
          Write-Host "expiring draft release $($r.tagName)"
          & gh release delete -R $repo $r.tagName --yes 2>$null | Out-Null
          $removed++
        }
      }
    } else {
      Write-Warning "gh release list unavailable; skipped"
    }
  }
} else {
  Write-Warning "no GITHUB_TOKEN; skipped release expiry"
}

Write-Host "cleanup done (removed=$removed)"


