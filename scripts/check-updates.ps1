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

# newest electron nightly = tag of the most recently UPDATED release on
# electron/nightlies. The rolling "nightly" tag is a permanent, ever-updated
# release (NOT the newest version), so sorting by published_at desc and taking
# the first is the correct "latest nightly version" signal.
# electron/nightlies has one rolling release tagged "nightly" that is updated
# in place every day — it is NOT the newest version tag. Fetch the recent
# release list and pick the newest genuine version tag (semver-descending,
# skip the rolling "nightly" tag and any non-version tags).
$rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/electron/nightlies/releases?per_page=100' -TimeoutSec 60
$candidates = @($rel | Where-Object {
  # nightly version tags look like "46.0.0-nightly.20261016" (no v-prefix).
  # Skip the rolling "nightly" tag and anything that isn't a versioned nightly.
  $_.tag_name -match '^\d+\.\d+\.\d+-nightly\.\d+$'
})
if ($candidates.Count -eq 0) { throw "no nightly version tags among $($rel.Count) releases" }
# sort key: 46.0.0-nightly.20261016 -> 46.0.0 (drop the -nightly.<date> suffix),
# compare as [version] descending so the newest MAJOR.minor.patch wins.
$nightly = ($candidates |
  Sort-Object { ([version]($_.tag_name -replace '-nightly\.\d+$','')) } -Descending |
  Select-Object -First 1).tag_name
if (-not $nightly) { throw "could not resolve newest nightly version from $($rel.Count) releases" }
Write-Host "newest electron nightly: $nightly"

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


