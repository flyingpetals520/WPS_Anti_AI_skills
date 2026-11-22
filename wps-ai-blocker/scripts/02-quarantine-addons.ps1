param(
  [string]$InstallRoot,
  [string]$QuarantineRoot = 'C:\WPSAI_Disabled',
  [switch]$WhatIf,
  [switch]$SkipTemp,
  [switch]$SkipRegistry
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'quarantine'

Write-WpsLog '=== QUARANTINE AI ADDONS ==='
if (-not $WhatIf -and (Get-WpsProcesses)) {
  Write-WpsLog 'WPS is running. Loaded AI DLLs may fail to move; close WPS if you see failures, then re-run.' 'WARN'
}

$installDst = Join-Path $QuarantineRoot 'install'
$poolDst = Join-Path $QuarantineRoot 'pool'
$tempDst = Join-Path $QuarantineRoot 'temp'
foreach ($d in @($installDst,$poolDst,$tempDst,(Join-Path $QuarantineRoot 'logs'))) {
  if (-not $WhatIf) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$roots = @(Get-WpsInstallRoots -InstallRoot $InstallRoot)
$totalMoved = 0; $totalFailed = 0

foreach ($a in @(Get-WpsAddonRoots -InstallRoots $roots)) {
  Write-WpsLog "Install addons: $a"
  $r = Move-WpsAiDirectories -Source $a -Destination $installDst -WhatIf:$WhatIf
  $totalMoved += $r.Moved; $totalFailed += $r.Failed
}

foreach ($p in @(Get-WpsPoolRoots)) {
  Write-WpsLog "Pool: $p"
  $r = Move-WpsAiDirectories -Source $p -Destination $poolDst -WhatIf:$WhatIf
  $totalMoved += $r.Moved; $totalFailed += $r.Failed
}

if (-not $SkipTemp) {
  foreach ($t in @(Get-WpsTempRoots)) {
    Write-WpsLog "Temp staging: $t"
    $r = Move-WpsAiDirectories -Source $t -Destination $tempDst -WhatIf:$WhatIf
    $totalMoved += $r.Moved; $totalFailed += $r.Failed
  }
}

# Move legacy in-tree quarantine folders outside the WPS tree.
foreach ($r in $roots) {
  foreach ($legacy in @(
    (Join-Path $r 'office6\addons_wpsai_disabled')
  )) {
    if (Test-Path $legacy) {
      Write-WpsLog "Legacy in-tree quarantine: $legacy"
      $r2 = Move-WpsAiDirectories -Source $legacy -Destination $installDst -WhatIf:$WhatIf
      $totalMoved += $r2.Moved; $totalFailed += $r2.Failed
      if (-not $WhatIf) { Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }
}
foreach ($p in @(Get-WpsPoolRoots)) {
  $parent = Split-Path $p -Parent
  Get-ChildItem $parent -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '_wpsai_disabled$' } | ForEach-Object {
    Write-WpsLog "Legacy in-tree pool quarantine: $($_.FullName)"
    $r2 = Move-WpsAiDirectories -Source $_.FullName -Destination $poolDst -WhatIf:$WhatIf
    $totalMoved += $r2.Moved; $totalFailed += $r2.Failed
    if (-not $WhatIf) { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

if (-not $SkipRegistry) {
  $n = Remove-WpsAiRegistry -WhatIf:$WhatIf
  Write-WpsLog ("Registry AI entries removed: {0}" -f $n)
}

Write-WpsLog ("SUMMARY moved={0} failed={1} quarantine={2}" -f $totalMoved, $totalFailed, $QuarantineRoot)
if ($totalFailed -gt 0) { exit 2 } else { exit 0 }
