#requires -Version 5.1
<#
.smoke.ps1 - run the upstream smoke test against a prepared ./vscode (channel-agnostic).

Needs Node on PATH and a compiled ./vscode (run build.ps1 first).
On Windows the smoke suite is minimal; this mainly verifies the host boots.
#>

[CmdletBinding()]
param(
  [Parameter()][ValidateSet('stable','insider')][string]$Channel = ''
)

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$VscodeDir = Join-Path $RepoRoot 'vscode'
if (-not (Test-Path $VscodeDir)) { throw "no ./vscode; prepare + build first" }

Push-Location $VscodeDir
try {
  & npm run smoketest 2>&1 | ForEach-Object { $_ }
  if ($LASTEXITCODE -ne 0) { throw "smoketest failed" }
} finally {
  Pop-Location
}
Write-Host "smoke OK ($Channel)"


