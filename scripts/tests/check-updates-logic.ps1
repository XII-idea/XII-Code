#requires -Version 5.1
# offline test: verify check-updates.ps1 diff logic (actions list) without network.
$ErrorActionPreference='Stop'
try { Set-StrictMode Latest } catch { }
$Root = (Split-Path -Parent $PSScriptRoot) | Split-Path -Parent
Set-Location $Root

$cases = @(
  # prev, cur, expected-actions
  ([pscustomobject]@{stable='';insider='';nightly=''},
   [pscustomobject]@{stable='1.142.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261005'},
   @('stable','insider','nightly')),
  ([pscustomobject]@{stable='1.142.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261005'},
   [pscustomobject]@{stable='1.142.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261005'},
   @()),
  ([pscustomobject]@{stable='1.142.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261005'},
   [pscustomobject]@{stable='1.143.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261005'},
   @('stable')),
  ([pscustomobject]@{stable='1.142.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261005'},
   [pscustomobject]@{stable='1.142.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261012'},
   @('nightly')),
  ([pscustomobject]@{stable='1.142.0';insider='1.143.0-insider';nightly='46.0.0-nightly.20261005'},
   [pscustomobject]@{stable='1.142.0';insider='1.144.0-insider';nightly='46.0.0-nightly.20261012'},
   @('insider','nightly'))
)

$fail = 0
for ($i=0; $i -lt $cases.Count; $i++) {
  $p = $cases[$i].prev; $c = $cases[$i].cur; $exp = $cases[$i].exp
  $actions = @()
  if ($c.stable -ne $p.stable)   { $actions += 'stable' }
  if ($c.insider -ne $p.insider) { $actions += 'insider' }
  if ($c.nightly -ne $p.nightly) { $actions += 'nightly' }
  $got = @($actions | Sort-Object) -join '|'
  $want = @($exp | Sort-Object) -join '|'
  $same = ($got -eq $want)
  if ($same) { Write-Host "case $i PASS -> [$(($exp -join ','))]" }
  else { Write-Host "case $i FAIL -> got [$($actions -join ',')] exp [$($exp -join ',')]"; $fail++ }
}
Write-Host "total failures: $fail"
if ($fail -gt 0) { exit 1 }
