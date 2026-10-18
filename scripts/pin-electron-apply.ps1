#requires -Version 5.1
<#
.pin-electron-apply.ps1 - apply an electron pin to an existing ./vscode clone.

Updates .npmrc target (keeps ms_build_id) and regenerates
build/checksums/electron.txt from the pinned release's SHASUMS256.txt.
Run by pin-electron.ps1 / prepare.ps1 when a clone exists.
#>

[CmdletBinding()]
param(
  [Parameter()][string]$VscodeDir,
  [Parameter(Mandatory)][string]$Version,
  [Parameter()][string]$MsBuildId = '0'
)

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }

if (-not $VscodeDir) { $VscodeDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'vscode' }
$Npmrc     = Join-Path $VscodeDir '.npmrc'
$Checksums = Join-Path $VscodeDir 'build/checksums/electron.txt'
if (-not (Test-Path $Npmrc)) { throw "$Npmrc not found" }

$raw = Get-Content $Npmrc -Raw
$q = [char]34
$targetLine = 'target=' + $q + $Version + $q
$raw = $raw -replace '(?m)^target=.*$', $targetLine
# ms_build_id must exist with quotes
$msLine = 'ms_build_id=' + $q + $MsBuildId + $q
if ($raw -notmatch '(?m)^ms_build_id=') {
  $raw = $raw.TrimEnd() + [Environment]::NewLine + $msLine + [Environment]::NewLine
} else {
  $raw = $raw -replace '(?m)^ms_build_id=.*$', $msLine
}
Set-Content -Path $Npmrc -Value $raw -Encoding UTF8
Write-Host "pinned .npmrc target=$Version"

# regenerate checksums
$shasumUrl = if ($Version -like '*nightly*') {
  "https://github.com/electron/nightlies/releases/download/v$Version/SHASUMS256.txt"
} else {
  "https://github.com/electron/electron/releases/download/v$Version/SHASUMS256.txt"
}
$shasum = Invoke-RestMethod -Uri $shasumUrl -TimeoutSec 60
Set-Content -Path $Checksums -Value $shasum -Encoding UTF8
Write-Host "regenerated $Checksums from $shasumUrl"


