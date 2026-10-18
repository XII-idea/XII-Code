#requires -Version 5.1
<#
.pin-electron.ps1 - pin the Electron version for XII Code builds.

Writes overlay/electron-pin.txt (target + ms_build_id) and, if a ./vscode
clone exists, also updates .npmrc + build/checksums/electron.txt.

The ms_build_id line must remain present in .npmrc (electronVersion.ts
reads it with a non-null regex). For OSS/nightly builds the value is only
kept for format compatibility; the actual download source is github
(electron/nightlies) per @electron/get.

Usage:
  .\scripts\pin-electron.ps1 -Version "46.0.0-nightly.20261005"
  .\scripts\pin-electron.ps1 -LatestNightly          # resolve newest nightly
  .\scripts\pin-electron.ps1 -Version "43.7.7"       # also accepts stable
#>

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Version = '',
  [Parameter()][switch]$LatestNightly
)

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }

$RepoRoot = Split-Path -Parent $PSScriptRoot
$PinFile  = Join-Path $RepoRoot 'overlay/electron-pin.txt'

function Resolve-LatestNightly {
  # Use the same tolerant logic as check-updates.ps1: the rolling "nightly"
  # release is updated in place every day, so the NEWEST version tag (by
  # semver) among the recent releases is the correct signal. Prefer an
  # authenticated call when GITHUB_TOKEN is present (CI) to avoid the shared
  # egress IP hitting the 60 req/h unauthenticated limit.
  $token = $env:GITHUB_TOKEN
  $accept = 'application/vnd.github+json'
  try {
    $h = @{ Accept = $accept }
    if ($token) { $h.Authorization = "token $token" }
    $rel = @(Invoke-RestMethod -Uri 'https://api.github.com/repos/electron/nightlies/releases?per_page=5' -Headers $h -TimeoutSec 60)
    $candidates = @($rel | Where-Object { $_.tag_name -match '^v?\d+\.\d+\.\d+-nightly\.\d+$' })
    if ($candidates.Count -eq 0) { throw "no nightly version tags in $($rel.Count) releases" }
    return (($candidates |
      Sort-Object { ([version]($_.tag_name -replace '^v','' -replace '-nightly\.\d+$','')) } -Descending |
      Select-Object -First 1).tag_name -replace '^v','')
  } catch {
    # last-resort: the rolling "nightly" release's own tag is a valid version
    $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/electron/nightlies/releases/tags/nightly' -TimeoutSec 30
    return $r.tag_name -replace '^v',''
  }
}

if ($LatestNightly) { $Version = Resolve-LatestNightly }
if (-not $Version) { throw "specify -Version or -LatestNightly" }
if ($Version -notmatch '^\d+\.\d+\.\d+') { throw "bad version '$Version'" }

$msBuildId = '0'
$pin = @"
# XII Code electron pin
# target is read by build/lib/electronVersion.ts; keep ms_build_id line present.
target=$Version
ms_build_id=$msBuildId
"@
Set-Content -Path $PinFile -Value $pin -Encoding UTF8
Write-Host "wrote $PinFile -> target=$Version"

# best-effort: sync an existing ./vscode clone
$vscodeDir = Join-Path $RepoRoot 'vscode'
if (Test-Path $vscodeDir) {
  & (Join-Path $PSScriptRoot 'pin-electron-apply.ps1') -VscodeDir $vscodeDir -Version $Version
} else {
  Write-Warning "no ./vscode clone; pin written, apply on next prepare"
}


