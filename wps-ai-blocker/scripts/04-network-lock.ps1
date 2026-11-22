param(
  [string]$InstallRoot,
  [string[]]$Domains,
  [switch]$FullOffline,
  [switch]$WhatIf
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'network'

if (-not (Test-IsAdmin)) {
  $a = @()
  if ($FullOffline) { $a += '-FullOffline' }
  if ($WhatIf) { $a += '-WhatIf' }
  if ($InstallRoot) { $a += @('-InstallRoot', $InstallRoot) }
  if ($Domains) { $a += @('-Domains', ($Domains -join ',')) }
  Ensure-Elevated -ScriptPath $PSCommandPath -Arguments $a
}

Write-WpsLog '=== NETWORK LOCK ==='
$useDomains = if ($Domains) { $Domains } else { $script:WpsAiDomains }

# Hosts block
$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
if (Test-Path $hosts) {
  $backupDir = Join-Path $env:TEMP 'wps-ai-blocker'
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  $bak = Join-Path $backupDir ('hosts-' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.bak')
  Copy-Item -LiteralPath $hosts -Destination $bak -Force
  Write-WpsLog "Hosts backup: $bak"
  try {
    $lines = Get-Content -LiteralPath $hosts -ErrorAction Stop
    $filtered = $lines | Where-Object {
      $line = $_
      -not ($useDomains | Where-Object { $line -match [regex]::Escape($_) }) -and
      $line -notmatch '^#\s*(BEGIN|END) WPS AI / UPDATE BLOCK'
    }
    $block = @('# BEGIN WPS AI / UPDATE BLOCK')
    foreach ($d in $useDomains) { $block += ('0.0.0.0 ' + $d) }
    $block += '# END WPS AI / UPDATE BLOCK'
    $tmp = Join-Path $env:TEMP 'hosts_wps_ai_block.txt'
    Set-Content -LiteralPath $tmp -Value (@($filtered) + $block) -Encoding ASCII
    if ($WhatIf) {
      Write-WpsLog "WHATIF hosts: would write $($useDomains.Count) domain blocks"
    } else {
      Copy-Item -LiteralPath $tmp -Destination $hosts -Force -ErrorAction Stop
      $check = Get-Content $hosts -Raw
      if ($check -match 'BEGIN WPS AI / UPDATE BLOCK' -and (Get-Item $hosts).Length -gt 0) {
        Write-WpsLog ("Hosts block written: {0} domains, size {1}" -f $useDomains.Count, (Get-Item $hosts).Length)
      } else {
        Write-WpsLog 'Hosts verification failed' 'WARN'
      }
    }
  } catch {
    Write-WpsLog ("Hosts write failed: {0}. Firewall is the primary block." -f $_.Exception.Message) 'WARN'
  }
} else {
  Write-WpsLog "Hosts file not found: $hosts" 'WARN'
}

# Firewall rules
if (-not $WhatIf) {
  Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'WPSAI_Block_*' } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

$roots = @(Get-WpsInstallRoots -InstallRoot $InstallRoot)
$exes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($r in $roots) {
  foreach ($rel in @('wtoolex\wpsupdate.exe','wtoolex\updateself.exe','wtoolex\updatepolicy.exe','ksolaunch.exe')) {
    $p = Join-Path $r $rel
    if (Test-Path $p) { [void]$exes.Add($p) }
  }
  if ($FullOffline) {
    Get-ChildItem (Join-Path $r 'office6') -File -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { [void]$exes.Add($_.FullName) }
    Get-ChildItem (Join-Path $r 'wtoolex') -File -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { [void]$exes.Add($_.FullName) }
    Get-ChildItem $r -File -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { [void]$exes.Add($_.FullName) }
  }
}

$updateCache = Join-Path $env:APPDATA 'kingsoft\office6\update\down'
if (Test-Path $updateCache) {
  Get-ChildItem $updateCache -File -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { [void]$exes.Add($_.FullName) }
}

$n = 0
foreach ($exe in $exes) {
  $n++
  $name = if ($FullOffline) { "WPSAI_Block_Net_$n" } else { "WPSAI_Block_Update_$n" }
  if ($WhatIf) {
    Write-WpsLog "WHATIF firewall block $exe"
    continue
  }
  try {
    New-NetFirewallRule -DisplayName $name -Direction Outbound -Program $exe -Action Block -Profile Any -Enabled True -ErrorAction Stop | Out-Null
    Write-WpsLog "FIREWALL BLOCK $exe"
  } catch {
    Write-WpsLog ("FIREWALL FAILED {0}: {1}" -f $exe, $_.Exception.Message) 'WARN'
  }
}

Write-WpsLog ("SUMMARY firewall programs blocked: {0}; full offline: {1}" -f $n, [bool]$FullOffline)
exit 0
