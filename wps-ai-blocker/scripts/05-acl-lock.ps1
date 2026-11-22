param(
  [string]$InstallRoot,
  [switch]$WhatIf
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'acl'

if (-not (Test-IsAdmin)) {
  $a = @()
  if ($WhatIf) { $a += '-WhatIf' }
  if ($InstallRoot) { $a += @('-InstallRoot', $InstallRoot) }
  Ensure-Elevated -ScriptPath $PSCommandPath -Arguments $a
}

Write-WpsLog '=== ACL LOCK ==='
$user = "$env:USERDOMAIN\$env:USERNAME"
$roots = @(Get-WpsInstallRoots -InstallRoot $InstallRoot)
$targets = @()
foreach ($a in @(Get-WpsAddonRoots -InstallRoots $roots)) { $targets += $a }
$targets += @(Get-WpsPoolRoots)
$targets = @($targets | Sort-Object -Unique)

if ($targets.Count -eq 0) {
  Write-WpsLog 'No addon/pool roots found; nothing to lock.' 'WARN'
  exit 1
}

foreach ($dir in $targets) {
  if (-not (Test-Path $dir)) { continue }
  if ($WhatIf) {
    Write-WpsLog "WHATIF deny (AD,WD) for $user on $dir"
    continue
  }
  Write-WpsLog "Deny (AD,WD) for $user on $dir"
  & icacls $dir /deny "${user}:(AD,WD)" 2>&1 | ForEach-Object { Write-WpsLog ("  " + $_) }
  $denied = Test-WpsCreateDenied $dir
  if ($denied -eq $true) {
    Write-WpsLog "PASS create denied: $dir" 'PASS'
  } elseif ($denied -eq $false) {
    Write-WpsLog "FAIL create still allowed: $dir" 'FAIL'
  } else {
    Write-WpsLog "SKIP path missing: $dir" 'WARN'
  }
}

Write-WpsLog 'NOTE: this also blocks non-AI addon installs and updates.'
exit 0
