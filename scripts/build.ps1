#requires -Version 5.1
<#
.build.ps1 - compile + package XII Code for a channel, output to dist/.

Prereqs: a prepared ./vscode (run prepare.ps1 first), Node + npm in PATH.
Windows: VS2022 C++ toolchain (cl on PATH). Linux: dpkg-deb + rpmbuild (deb/rpm).

Supported targets:
  win32-x64, win32-arm64        (setup.exe via Inno, user or system install)
  linux-x64, linux-arm64        (.deb via dpkg-deb, .rpm via rpmbuild)

Usage:
  .\scripts\build.ps1 -Channel stable -Target win32-x64
  .\scripts\build.ps1 -Channel insider -Target linux-arm64 -Formats deb,rpm
  .\scripts\build.ps1 -Channel stable -Target win32-x64 -Setup system

Outputs land under dist/<channel>/<platform>-<arch>/...
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('stable','insider')][string]$Channel,
  [Parameter(Mandatory)][ValidateSet('win32-x64','win32-arm64','linux-x64','linux-arm64')][string]$Target,
  [Parameter()][ValidateSet('user','system')][string]$Setup = 'user',
  # win: 'none'|'min'|'dir'|'setup'   linux: 'deb'|'rpm'|'deb,rpm'
  [Parameter()][string]$Formats = 'setup',
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }

# validate -Formats up-front (ValidateSet can't express the comma combos)
$validFormats = @('none','min','dir','setup','deb','rpm','deb,rpm')
if ($Formats -notin $validFormats) {
  throw "invalid -Formats '$Formats'; allowed: $($validFormats -join ', ')"
}

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$VscodeDir = Join-Path $RepoRoot 'vscode'
if (-not (Test-Path $VscodeDir)) { throw "no ./vscode; run prepare.ps1 -Channel $Channel -Target $Target first" }

$platform, $arch = $Target -split '-'
$isWin = ($platform -eq 'win32')
$gulpPrefix = "vscode-$platform-$arch"

# resolve which gulp task(s) to run
$tasks = @()
if ($isWin) {
  switch ($Formats) {
    'setup' { $tasks += "$gulpPrefix-$Setup-setup" }
    'dir'   { $tasks += $gulpPrefix }
    'min'   { $tasks += "$gulpPrefix-min" }
    'none'  { $tasks += $gulpPrefix }
  }
} else {
  # linux: -Formats takes 'deb','rpm' (both allowed)
  $wantDeb = $Formats -split ',' -contains 'deb'
  $wantRpm = $Formats -split ',' -contains 'rpm'
  if (-not $wantDeb -and -not $wantRpm) { $wantDeb = $true }
  if ($wantDeb) { $tasks += "$gulpPrefix-prepare-deb", "$gulpPrefix-build-deb" }
  if ($wantRpm) { $tasks += "$gulpPrefix-prepare-rpm", "$gulpPrefix-build-rpm" }
}

$destRoot = Join-Path $RepoRoot "dist/$Channel/$platform-$arch"
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null

Push-Location $VscodeDir
try {
  if (-not $SkipInstall) {
    Write-Host "npm install ..."
    & npm install 2>&1 | ForEach-Object { $_ }
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
  }

  # win32 setup also needs the unpacked source dir; run the packaging dir task first
  if ($isWin -and $Formats -eq 'setup' -and $tasks -notcontains $gulpPrefix) {
    Write-Host "gulp $gulpPrefix (prepare source dir) ..."
    & npm run gulp -- $gulpPrefix 2>&1 | ForEach-Object { $_ }
    if ($LASTEXITCODE -ne 0) { throw "gulp $gulpPrefix failed" }
  }

  foreach ($t in $tasks) {
    Write-Host "gulp $t ..."
    & npm run gulp -- $t 2>&1 | ForEach-Object { $_ }
    if ($LASTEXITCODE -ne 0) { throw "gulp $t failed" }
  }

  # collect produced artifacts
  $produced = @()
  if ($isWin) {
    # Inno setup .exe lands in .build/win32-<arch>/<setup>-setup/
    $setupOut = Join-Path $VscodeDir ".build/$platform-$arch/$Setup-setup"
    if (Test-Path $setupOut) {
      $produced += (Get-ChildItem $setupOut -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue).FullName
    }
  } else {
    $debArch = if ($arch -eq 'x64') { 'amd64' } else { $arch }
    $rpmArch = if ($arch -eq 'x64') { 'x86_64' } elseif ($arch -eq 'arm64') { 'aarch64' } else { $arch }
    $debOut = Join-Path $VscodeDir ".build/linux/deb/$debArch"
    $rpmOut = Join-Path $VscodeDir ".build/linux/rpm/$rpmArch"
    if (Test-Path $debOut) { $produced += (Get-ChildItem $debOut -Filter '*.deb' -Recurse -ErrorAction SilentlyContinue).FullName }
    if (Test-Path $rpmOut) { $produced += (Get-ChildItem $rpmOut -Filter '*.rpm' -Recurse -ErrorAction SilentlyContinue).FullName }
  }
  foreach ($p in $produced) {
    if ($p -and (Test-Path $p)) { Copy-Item $p $destRoot -Force; Write-Host "collected $(Split-Path $p -Leaf)" }
  }
  if ($produced.Count -eq 0) { Write-Warning "no artifacts found in expected locations under .build" }
  Write-Host "artifacts in $destRoot :"
  Get-ChildItem $destRoot -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
} finally {
  Pop-Location
}
