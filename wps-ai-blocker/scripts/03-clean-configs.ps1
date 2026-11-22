param(
  [string]$InstallRoot,
  [switch]$WhatIf,
  [switch]$SkipRegistry
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'configs'

Write-WpsLog '=== CLEAN WPS AI CONFIG ENTRIES ==='
$roots = @(Get-WpsInstallRoots -InstallRoot $InstallRoot)
$total = 0

foreach ($r in $roots) {
  Write-WpsLog "Install root: $r"
  $plg = Join-Path $r 'office6\setupplugincfg\setupplugin.plg'
  $applist = Join-Path $r 'office6\addons\kapplist\applist.xml'
  $crc = Join-Path $r 'utility\crcmap.dat'
  $ifl = Join-Path $r 'utility\installfilelist.dat'

  if (Test-Path $plg) {
    $total += (Remove-WpsAiLinesFromTextFile -Path $plg -Encoding UTF8 -LineSeparator "`r`n" -WhatIf:$WhatIf)
  }
  if (Test-Path $applist) {
    $total += (Remove-WpsAiLinesFromTextFile -Path $applist -Encoding UTF8 -LineSeparator "`n" -WhatIf:$WhatIf)
  }
  if (Test-Path $crc) {
    $total += (Remove-WpsAiLinesFromManifest -Path $crc -Encoding Unicode -WhatIf:$WhatIf)
  }
  if (Test-Path $ifl) {
    $total += (Remove-WpsAiLinesFromManifest -Path $ifl -Encoding Legacy -WhatIf:$WhatIf)
  }
}

foreach ($p in @(Get-WpsPoolRoots)) {
  Get-ChildItem $p -Directory -Filter 'kapplist_*' -ErrorAction SilentlyContinue | ForEach-Object {
    $f = Join-Path $_.FullName 'applist.xml'
    if (Test-Path $f) {
      Write-WpsLog "Pool applist: $f"
      $total += (Remove-WpsAiLinesFromTextFile -Path $f -Encoding UTF8 -LineSeparator "`n" -WhatIf:$WhatIf)
    }
  }
}

if (-not $SkipRegistry) {
  $n = Remove-WpsAiRegistry -WhatIf:$WhatIf
  Write-WpsLog ("Registry AI entries removed: {0}" -f $n)
  $total += $n
}

Write-WpsLog ("SUMMARY config lines/entries removed: {0}" -f $total)
exit 0
