param(
  [switch]$WhatIf
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'guard-install'

if (-not (Test-IsAdmin)) {
  $a = @()
  if ($WhatIf) { $a += '-WhatIf' }
  Ensure-Elevated -ScriptPath $PSCommandPath -Arguments $a
}

Write-WpsLog '=== INSTALL WPSAI_GUARD ==='
$guardDir = 'C:\ProgramData\WPSAI_Guard'
$guardScript = Join-Path $guardDir 'wpsai_guard.ps1'
$commonDst = Join-Path $guardDir '00-common.ps1'

if ($WhatIf) {
  Write-WpsLog "WHATIF create $guardDir"
  Write-WpsLog "WHATIF copy 00-common.ps1 and guard-template.ps1"
  Write-WpsLog "WHATIF register task WPSAI_Guard (AtLogOn + every 10 minutes, Highest)"
  exit 0
}

New-Item -ItemType Directory -Path $guardDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '00-common.ps1') -Destination $commonDst -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'guard-template.ps1') -Destination $guardScript -Force
Write-WpsLog "Guard script: $guardScript"

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\WPSAI_Guard\wpsai_guard.ps1"'
$t1 = New-ScheduledTaskTrigger -AtLogOn
$t2 = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

try {
  Register-ScheduledTask -TaskName 'WPSAI_Guard' -Action $action -Trigger @($t1,$t2) -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
  Write-WpsLog 'Task WPSAI_Guard registered (AtLogOn + 10-minute repetition, Highest).' 'PASS'
} catch {
  Write-WpsLog ("Task registration failed: {0}" -f $_.Exception.Message) 'FAIL'
  exit 1
}

Start-ScheduledTask -TaskName 'WPSAI_Guard' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 6
$log = Join-Path $guardDir 'guard.log'
if (Test-Path $log) {
  Write-WpsLog ("Guard log tail: {0}" -f ((Get-Content $log -Tail 3) -join ' | '))
} else {
  Write-WpsLog 'Guard log not created yet; the task may still be starting.' 'WARN'
}

Write-WpsLog '=== GUARD INSTALL COMPLETE ==='
exit 0
