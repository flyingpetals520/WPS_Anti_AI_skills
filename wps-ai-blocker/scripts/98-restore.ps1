param(
  [string]$InstallRoot,
  [string]$QuarantineRoot = 'C:\WPSAI_Disabled',
  [switch]$WhatIf
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'restore'

if (-not (Test-IsAdmin)) {
  $a = @()
  if ($WhatIf) { $a += '-WhatIf' }
  if ($InstallRoot) { $a += @('-InstallRoot', $InstallRoot) }
  Ensure-Elevated -ScriptPath $PSCommandPath -Arguments $a
}

Write-WpsLog '=== RESTORE WPS AI BLOCKER ==='
$user = "$env:USERDOMAIN\$env:USERNAME"
$roots = @(Get-WpsInstallRoots -InstallRoot $InstallRoot)
$pools = @(Get-WpsPoolRoots)

# Firewall
if ($WhatIf) {
  Write-WpsLog 'WHATIF remove firewall rules WPSAI_Block_*'
} else {
  Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'WPSAI_Block_*' } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
  Write-WpsLog 'Removed firewall rules WPSAI_Block_*'
}

# Guard task
if ($WhatIf) {
  Write-WpsLog 'WHATIF unregister WPSAI_Guard'
} else {
  Unregister-ScheduledTask -TaskName 'WPSAI_Guard' -Confirm:$false -ErrorAction SilentlyContinue
  Write-WpsLog 'Unregistered WPSAI_Guard'
}

# Hosts
$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
$backup = Get-ChildItem -Path @(
  (Join-Path $env:TEMP 'wps-ai-blocker\hosts-*.bak'),
  (Join-Path $env:TEMP 'hosts_before_wpsai_*.txt')
) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($backup) {
  if ($WhatIf) {
    Write-WpsLog "WHATIF restore hosts from $($backup.FullName)"
  } else {
    Copy-Item -LiteralPath $backup.FullName -Destination $hosts -Force -ErrorAction SilentlyContinue
    Write-WpsLog "Hosts restored from $($backup.FullName)"
  }
} else {
  Write-WpsLog 'No hosts backup found; remove the WPS block manually.' 'WARN'
}

# ACL
foreach ($d in @(@(Get-WpsAddonRoots -InstallRoots $roots) + $pools)) {
  if ($WhatIf) {
    Write-WpsLog "WHATIF remove deny ACL on $d"
  } else {
    & icacls $d /remove:d $user 2>&1 | ForEach-Object { Write-WpsLog ("  " + $_) }
    Write-WpsLog "Removed deny ACL on $d"
  }
}

Write-WpsLog "Quarantine remains at: $QuarantineRoot"
Write-WpsLog 'Config backups remain next to each edited file as *.wpsai_bak_*'
Write-WpsLog 'Move quarantine folders back manually if you want the AI addons restored.'
Write-WpsLog 'Restart WPS after restoring network/ACL settings.'
exit 0
