#requires -Version 5.1
# offline test harness: fake ./vscode layout, run prepare -SkipClone -Offline, assert brand merge
$ErrorActionPreference='Stop'
try { try { Set-StrictMode Latest } catch { } } catch { }
$here = Split-Path -Parent $PSScriptRoot
$Root = Join-Path $here '..'   # XII-Code
$root = $Root
Set-Location $root

# ---- fixtures ----
# fake upstream product.json
$up = [ordered]@{
  nameShort='Code - OSS'; nameLong='Code - OSS'; applicationName='code-oss'
  dataFolderName='.vscode-oss'; quality='stable'; updateUrl='https://x'
  licenseName='MIT'
  version='1.142.0'
}
# fake .npmrc
# fake checksums
$vd = Join-Path $root 'vscode'
New-Item -ItemType Directory -Force -Path $vd | Out-Null
$upJson = $up | ConvertTo-Json -Depth 8
Set-Content (Join-Path $vd 'product.json') $upJson -Encoding UTF8
$nl = [Environment]::NewLine
$q = [char]34
$npmrc = "disturl=" + $q + "https://electronjs.org/headers" + $q + $nl +
         "target=" + $q + "43.7.7" + $q + $nl +
         "ms_build_id=" + $q + "15553055" + $q + $nl
Set-Content (Join-Path $vd '.npmrc') $npmrc -Encoding UTF8
# pin file (key=value with double quotes, .npmrc style)
$pin = "target=" + $q + "46.0.0-nightly.20261005" + $q + $nl +
       "ms_build_id=" + $q + "0" + $q + $nl
Set-Content (Join-Path $root 'overlay\electron-pin.txt') $pin -Encoding UTF8
New-Item -ItemType Directory -Force -Path (Join-Path $vd 'build\checksums') | Out-Null
Set-Content (Join-Path $vd 'build\checksums\electron.txt') "OLD" -Encoding UTF8

# ---- run prepare (offline, skip clone); reset the two target lines first so
#      the idempotent replace has a clean starting point ----
& (Join-Path $root 'scripts\prepare.ps1') -Channel stable -SkipClone -Offline 2>&1 | ForEach-Object { Write-Host "  " $_ }
# run a second time to prove idempotency (must NOT double-quote)
& (Join-Path $root 'scripts\prepare.ps1') -Channel stable -SkipClone -Offline 2>&1 | Out-Null

# ---- assertions ----
$merged = Get-Content (Join-Path $vd 'product.json') -Raw | ConvertFrom-Json
Write-Host "== merged product.json =="
Write-Host "nameShort      = $($merged.nameShort)   (expect 'XII Code')"
Write-Host "applicationName= $($merged.applicationName)   (expect 'xiicode')"
Write-Host "quality        = $($merged.quality)   (expect 'stable' preserved, NOT overwritten)"
Write-Host "updateUrl      = $($merged.updateUrl)   (expect 'https://x' preserved)"
Write-Host "licenseName    = $($merged.licenseName)   (expect 'MIT' preserved)"
Write-Host "version        = $($merged.version)   (expect '1.142.0' preserved)"
$ok = $merged.nameShort -eq 'XII Code' -and $merged.applicationName -eq 'xiicode' -and $merged.licenseName -eq 'MIT'
Write-Host "merge-check: $(if($ok){'PASS'}else{'FAIL'})"

$npmrc2 = Get-Content (Join-Path $vd '.npmrc') -Raw
# single, exact quote: target="46.0.0-nightly.20261005"
$chk = [regex]::IsMatch($npmrc2, '(?m)^target="46\.0\.0-nightly\.20261005"$')
$chk2 = [regex]::IsMatch($npmrc2, '(?m)^ms_build_id="0"$')
$noDouble = -not ($npmrc2 -match '""')
Write-Host "npmrc lines:"
$npmrc2 -split "`n" | ForEach-Object { Write-Host "  |$_" }
Write-Host "npmrc target=$chk ms_build_id=$chk2 noDoubleQuote=$noDouble (expect True/True/True)"
Write-Host "npmrc-check: $(if($chk -and $chk2 -and $noDouble){'PASS'}else{'FAIL'})"

$cs = (Get-Content (Join-Path $vd 'build\checksums\electron.txt') -Raw).Trim()
$csOk = $cs -eq 'OLD'
Write-Host "checksums untouched (offline) = $csOk (expect True)"
Write-Host "cleanup-check: $(if($csOk){'PASS'}else{'FAIL'})"

