#requires -Version 5.1
<#
.\prepare.ps1 - prepare the upstream VS Code source for XII Code build.

Pipeline (per channel):
  1. shallow-clone microsoft/vscode into ./vscode at the channel's source
  2. deep-merge overlay/product.json (or product.insider.json) into vscode/product.json
  3. apply the brand patch to build/lib/electron.ts (company/copyright)
  4. pin electron: write .npmrc target (+ ms_build_id kept) and regenerate build/checksums/electron.txt

Source of the upstream ref:
  - stable  : official stable channel's latest version (resolved online unless -VscodeBranch is given)
  - insider : main branch (unless -VscodeBranch is given)

Run check-updates first to learn which version to build.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateSet('stable', 'insider')]
  [string]$Channel,

  [Parameter()]
  [string]$VscodeBranch = '',

  [Parameter()]
  [switch]$SkipClone,

  [Parameter()]
  [switch]$Offline,

  [Parameter()]
  [ValidateSet('win32-x64','win32-arm64','linux-x64','linux-arm64','auto')]
  [string]$Target = 'auto'
)
# param notes:
#   -Channel       'stable'|'insider' (required)
#   -VscodeBranch  explicit branch/tag/commit; overrides the channel default
#   -SkipClone     reuse existing ./vscode (skip clone+checkout)
#   -Offline       no network; use local ./vscode only
#   -Target        architecture hint; 'auto' = host arch. Used for icon/resource
#                  overlays and for cross-build arch on the native side.

$ErrorActionPreference = 'Stop'
try { Set-StrictMode Latest } catch { }

# ---- paths ---------------------------------------------------------------
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$VscodeDir  = Join-Path $RepoRoot 'vscode'
$Npmrc      = Join-Path $VscodeDir '.npmrc'
$Checksums  = Join-Path $VscodeDir 'build\checksums\electron.txt'
$PatchesDir = Join-Path $RepoRoot 'patches'
$OverlayDir = Join-Path $RepoRoot 'overlay'
# Resolve git + bash across Windows (MSYS) and Linux (system) runners.
$GitCmd = $null
$GitBash = $null
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
  foreach ($cand in @('D:\Program Files\Git\bin\bash.exe','C:\Program Files\Git\bin\bash.exe','bash')) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $GitBash = $cmd.Source; break }
  }
  foreach ($cand in @('D:\Program Files\Git\cmd\git.exe','C:\Program Files\Git\cmd\git.exe','git')) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $GitCmd = $cmd.Source; break }
  }
} else {
  # Linux runner: git on PATH; bash is /bin/bash (we only invoke git clone/apply,
  # so bash isn't strictly needed, but keep a fallback in case of MSYS tooling).
  $GitCmd = 'git'
  $GitBash = 'bash'
}
if (-not $GitCmd) { throw "git not found on this runner" }
Write-Host "using git: $GitCmd ; bash: $GitBash"

# ---- 0. electron pin file lives in overlay (source of truth) -----------
$PinFile = Join-Path $OverlayDir 'electron-pin.txt'
$electronVersion = ''
$msBuildId = ''
if (Test-Path $PinFile) {
  $raw = Get-Content $PinFile -Raw
  # Split on \n, then trim both \r and " so CRLF (git autocrlf) or a
  # malformed write like "target"46..." still parse.
  foreach ($line in ($raw -split "`n")) {
    $line = $line.Trim().Trim("`r").Trim('"')
    if (-not $line -or $line.StartsWith('#')) { continue }
    # normalize: drop a leading quote-only key like "target" -> target
    $line2 = $line -replace '^target', 'target' -replace '^ms_build_id', 'ms_build_id'
    $kv = $line2.Split('=', 2)
    if ($kv.Count -ne 2) { continue }
    switch ($kv[0].Trim().Trim('"')) {
      'target'      { $electronVersion = $kv[1].Trim().Trim('"') }
      'ms_build_id' { $msBuildId = $kv[1].Trim().Trim('"') }
    }
  }
}
if (-not $electronVersion) {
  throw "No Electron pin found. Run .\scripts\pin-electron.ps1 first to create $PinFile"
}

# ---- 1. clone / checkout ------------------------------------------------
if (-not $SkipClone) {
  if ($VscodeBranch) {
    $ref = $VscodeBranch
  } elseif ($Channel -eq 'insider') {
    $ref = 'main'
  } else {
    if ($Offline) { throw "stable channel needs the network to resolve the tag unless -VscodeBranch is set" }
    # latest official stable version, e.g. "1.142.0" -> clone that tag
    $stable = Invoke-RestMethod -Uri 'https://update.code.visualstudio.com/api/releases/stable' -TimeoutSec 30
    $ref = $stable[0]
    Write-Host "stable channel -> upstream tag $ref"
  }

  if (Test-Path $VscodeDir) {
    Remove-Item -Recurse -Force $VscodeDir
  }
  Write-Host "Cloning microsoft/vscode @ $ref into $VscodeDir ..."
  $cloneScript = "set -e" + [char]10 +
    "cd '" + $RepoRoot.Replace('\','/') + "'" + [char]10 +
    "git clone --branch '" + $ref + "' --depth 1 https://github.com/microsoft/vscode.git vscode"
  & $GitBash --login -c $cloneScript
  if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
} else {
  if (-not (Test-Path $VscodeDir)) { throw "$VscodeDir missing and -SkipClone set" }
  Write-Host "Reusing existing $VscodeDir (skip clone)"
}

# ---- 2. merge brand into product.json (whitelist) -----------------------
if ($Channel -eq 'insider') { $ovPath = Join-Path $OverlayDir 'product.insider.json' } else { $ovPath = Join-Path $OverlayDir 'product.json' }
$upPath = Join-Path $VscodeDir 'product.json'
if (-not (Test-Path $ovPath)) { throw "overlay $ovPath not found" }

$whitelist = @(
  'nameShort','nameLong','applicationName','dataFolderName','sharedDataFolderName',
  'win32MutexName','win32DirName','win32NameVersion','win32RegValueName',
  'win32AppUserModelId','win32ShellNameShort','win32TunnelServiceMutex','win32TunnelMutex',
  'win32x64AppId','win32arm64AppId','win32x64UserAppId','win32arm64UserAppId',
  'darwinBundleIdentifier','darwinProfileUUID','darwinProfilePayloadUUID',
  'linuxDesktopName','linuxIconName','urlProtocol','reportIssueUrl',
  'serverApplicationName','serverDataFolderName','tunnelApplicationName'
)
$base = Get-Content $upPath -Raw | ConvertFrom-Json
$ov   = Get-Content $ovPath -Raw | ConvertFrom-Json
$merged = [ordered]@{}
foreach ($p in $base.PSObject.Properties) { $merged[$p.Name] = $p.Value }
foreach ($k in $ov.PSObject.Properties.Name) {
  if ($k -eq 'quality' -or $k -eq 'updateUrl') { throw "overlay key '$k' is forbidden (see AGENTS.md §3)" }
  if ($whitelist -contains $k) { $merged[$k] = $ov.$k }
  else { Write-Warning "overlay key '$k' not in whitelist; ignored" }
}
$json = $merged | ConvertTo-Json -Depth 16
Set-Content -Path $upPath -Value $json -Encoding UTF8
Write-Host "merged brand fields from $(Split-Path $ovPath -Leaf) into $upPath"

# ---- 3. apply the brand patch (company/copyright) ----------------------
$patch = Join-Path $PatchesDir '0001-electron-config.patch'
if (Test-Path $patch) {
  # the patch's context lines match current main; apply idempotently
  $applyScript = "set -e" + [char]10 +
    "cd '" + $VscodeDir.Replace('\','/') + "'" + [char]10 +
    "if git apply --check '" + $patch.Replace('\','/') + "' 2>/dev/null; then git apply '" + $patch.Replace('\','/') + "'; else echo 'patch already applied or no context; skipping'; fi"
  & $GitBash --login -c $applyScript
  if ($LASTEXITCODE -ne 0) { throw "patch apply failed (exit $LASTEXITCODE)" }
} else {
  Write-Warning "no patch at $patch; skipping"
}

# ---- 3b. copy brand icon + linux resources into upstream ----------------
$sep = [System.IO.Path]::DirectorySeparatorChar
$winIco = Join-Path $OverlayDir ("win32" + $sep + "code.ico")
if (Test-Path $winIco) {
  $upWinIco = Join-Path $VscodeDir ("resources" + $sep + "win32" + $sep + "code.ico")
  if (Test-Path (Split-Path $upWinIco)) { Copy-Item $winIco $upWinIco -Force; Write-Host "copied win32 icon -> $upWinIco" }
}
$lnIco = Join-Path $OverlayDir ("linux" + $sep + "code.png")
$lnSvg = Join-Path $OverlayDir ("linux" + $sep + "code.svg")
if ((Test-Path $lnIco) -or (Test-Path $lnSvg)) {
  $lnRes = Join-Path $VscodeDir ('resources' + $sep + 'linux')
  if (Test-Path $lnRes) {
    if (Test-Path $lnIco) { Copy-Item $lnIco (Join-Path $lnRes 'code.png') -Force }
    if (Test-Path $lnSvg) { Copy-Item $lnSvg (Join-Path $lnRes 'code.svg') -Force }
    # point .desktop / appdata at our product names (template vars)
    $prod = Get-Content (Join-Path $VscodeDir 'product.json') -Raw | ConvertFrom-Json
    foreach ($tpl in @('code.desktop','code-url-handler.desktop')) {
      $p = Join-Path $lnRes $tpl
      if (Test-Path $p) {
        $c = Get-Content $p -Raw
        $c = $c -replace '@@PRODNAME@@',$prod.nameLong -replace '@@APPNAME@@',$prod.applicationName
        Set-Content $p $c -Encoding UTF8
      }
    }
    $appdata = Join-Path $lnRes 'code.appdata.xml'
    if (Test-Path $appdata) {
      $c = Get-Content $appdata -Raw
      $c = $c -replace '@@PRODNAME@@',$prod.nameLong -replace '@@APPNAME@@',$prod.applicationName
      Set-Content $appdata $c -Encoding UTF8
    }
    Write-Host "overlaid linux resources (desktop/icon)"
  }
}

# ---- 4. pin electron -----------------------------------------------------
if (-not (Test-Path $Npmrc)) { throw "$Npmrc not found" }
$raw = Get-Content $Npmrc -Raw
$q = [char]34
$targetLine = 'target=' + $q + $electronVersion + $q
# trim \r before the line so CRLF files don't leave a trailing \r
$raw = $raw -replace '(?m)^target=.*$', $targetLine
# ms_build_id must remain present with quotes (electronVersion.ts regex reads the quoted value)
$msLine = 'ms_build_id=' + $q + $msBuildId + $q
if ($raw -notmatch '(?m)^ms_build_id=') {
  $raw = $raw.TrimEnd() + [Environment]::NewLine + $msLine + [Environment]::NewLine
} else {
  $raw = $raw -replace '(?m)^ms_build_id=.*$', $msLine
}
Set-Content -Path $Npmrc -Value $raw -Encoding UTF8
Write-Host "pinned .npmrc target=$electronVersion (ms_build_id=$msBuildId)"

# regenerate the checksum file from the pinned release
if (-not $Offline) {
  $shasumUrl = if ($electronVersion -like '*nightly*') {
    "https://github.com/electron/nightlies/releases/download/v$electronVersion/SHASUMS256.txt"
  } else {
    "https://github.com/electron/electron/releases/download/v$electronVersion/SHASUMS256.txt"
  }
  $shasum = Invoke-RestMethod -Uri $shasumUrl -TimeoutSec 60
  Set-Content -Path $Checksums -Value $shasum -Encoding UTF8
  Write-Host "regenerated $Checksums from $shasumUrl"
} else {
  Write-Warning "offline: left $Checksums untouched"
}

# surface the pin to callers (detect/matrix jobs can read this)
$pinOut = [ordered]@{ target = $electronVersion; ms_build_id = $msBuildId }
$pinOut | ConvertTo-Json | Set-Content (Join-Path $RepoRoot '.cache/electron-pin.json') -Encoding UTF8

Write-Host "`nprepare OK: channel=$channel electron=$electronVersion ref=$ref"

