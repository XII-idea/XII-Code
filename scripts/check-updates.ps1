#requires -Version 5.1
<#
.check-updates.ps1 - detect the latest upstream versions and Electron nightly.

Outputs JSON to stdout (consumed by ci.yml and humans):
  {
    "stable": "1.142.0",
    "insider": "1.143.0-insider",
    "nightly": "46.0.0-nightly.20261005",
    "prevStable": "...", "prevInsider": "...", "prevNightly": "...",
    "actions": ["stable","insider","nightly"]
  }
"actions" lists which sources CHANGED since the last run (state in ./.cache/
check-updates.json). If no prev state exists, all three are treated as changed.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }
$RepoRoot = Split-Path -Parent $PSScriptRoot
$cacheDir = Join-Path $RepoRoot '.cache'
$cacheFile = Join-Path $cacheDir 'check-updates.json'

function Get-First { param([string]$url) $r = Invoke-RestMethod -Uri $url -TimeoutSec 30; return $r[0] }

$stable = Get-First 'https://update.code.visualstudio.com/api/releases/stable'
$insider = Get-First 'https://update.code.visualstudio.com/api/releases/insider'

# newest electron nightly = the newest version tag on electron/nightlies.
# The rolling "nightly" tag is a permanent release updated in place every day
# (NOT the newest version tag), so we must pick the highest MAJOR.minor.patch
# among the genuine version tags.
#
# Rate-limit handling:
#   - CI (windows-latest) shares an egress IP that exhausts the unauthenticated
#     60 req/h GitHub limit fast. GITHUB_TOKEN is present on CI (ci.yml grants
#     contents: write), and authenticated calls get 5000 req/h — so when a token
#     is available we issue ONE per_page=1 call (most-recently-updated release,
#     which is the rolling "nightly" build).
#   - local (no token) falls back to an unauthenticated per_page=5 list and sorts.
# If the nightly source fails entirely (rate limit / outage) we DO NOT throw:
# stable/insider detection is independent, and the caller (ci.yml) treats an
# empty nightly as "keep the existing pin, skip auto-bump".
function Get-LatestNightly {
  $token = $env:GITHUB_TOKEN
  $accept = 'application/vnd.github+json'
  try {
    if ($token) {
      $h = @{ Authorization = "token $token"; Accept = $accept }
      $uri = 'https://api.github.com/repos/electron/nightlies/releases?per_page=1'
      $first = Invoke-RestMethod -Uri $uri -Headers $h -TimeoutSec 60
      if ($first.tag_name -match '^v?\d+\.\d+\.\d+-nightly\.\d+$') {
        return $first.tag_name -replace '^v',''
      }
    }
    # fallback: list a few releases and pick the newest version tag
    $h = @{ Accept = $accept }
    if ($token) { $h.Authorization = "token $token" }
    $uri = 'https://api.github.com/repos/electron/nightlies/releases?per_page=5'
    $rel = @(Invoke-RestMethod -Uri $uri -Headers $h -TimeoutSec 60)
    $candidates = @($rel | Where-Object { $_.tag_name -match '^v?\d+\.\d+\.\d+-nightly\.\d+$' })
    if ($candidates.Count -eq 0) { return $null }
    return (($candidates |
      Sort-Object { ([version]($_.tag_name -replace '^v','' -replace '-nightly\.\d+$','')) } -Descending |
      Select-Object -First 1).tag_name -replace '^v','')
  } catch {
    Write-Warning "Get-LatestNightly: $($_.Exception.Message)"
    return $null
  }
}
$nightly = Get-LatestNightly
if ($nightly) {
  Write-Host "newest electron nightly: $nightly"
} else {
  Write-Warning "could not resolve newest nightly (rate limit or outage); keeping existing pin"
  $nightly = ''
}

$prevStable = ''; $prevInsider = ''; $prevNightly = ''
if (Test-Path $cacheFile) {
  $c = Get-Content $cacheFile -Raw | ConvertFrom-Json
  $prevStable = [string]$c.stable; $prevInsider = [string]$c.insider; $prevNightly = [string]$c.nightly
}

$actions = @()
if ($stable -ne $prevStable)   { $actions += 'stable' }
if ($insider -ne $prevInsider) { $actions += 'insider' }
if ($nightly -ne $prevNightly) { $actions += 'nightly' }

# persist new state
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
[pscustomobject]@{ stable=$stable; insider=$insider; nightly=$nightly } |
  ConvertTo-Json | Set-Content $cacheFile -Encoding UTF8

$out = [ordered]@{
  stable=$stable; insider=$insider; nightly=$nightly
  prevStable=$prevStable; prevInsider=$prevInsider; prevNightly=$prevNightly
  actions=$actions
}
$out | ConvertTo-Json -Depth 5


