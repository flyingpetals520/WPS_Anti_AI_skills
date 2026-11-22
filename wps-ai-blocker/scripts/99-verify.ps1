param(
  [string]$InstallRoot,
  [string]$QuarantineRoot = 'C:\WPSAI_Disabled'
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'verify'

$script:Pass = 0
$script:Fail = 0
function Add-Check {
  param([string]$Name, [bool]$Ok, [string]$Detail = '')
  if ($Ok) {
    Write-WpsLog ("PASS  {0} {1}" -f $Name, $Detail) 'PASS'
    $script:Pass++
  } else {
    Write-WpsLog ("FAIL  {0} {1}" -f $Name, $Detail) 'FAIL'
    $script:Fail++
  }
}

Write-WpsLog '=== WPS AI BLOCKER VERIFY ==='
$roots = @(Get-WpsInstallRoots -InstallRoot $InstallRoot)
$pools = @(Get-WpsPoolRoots)
$temps = @(Get-WpsTempRoots)
$addonRoots = @(Get-WpsAddonRoots -InstallRoots $roots)

$aiAddons = @()
foreach ($a in $addonRoots) { $aiAddons += @(Get-WpsAiDirectories $a) }
$aiPools = @()
foreach ($p in $pools) { $aiPools += @(Get-WpsAiDirectories $p) }
$aiTemps = @()
foreach ($t in $temps) { $aiTemps += @(Get-WpsAiDirectories $t) }
Add-Check 'AI dirs in install addons' ($aiAddons.Count -eq 0) ("count={0}" -f $aiAddons.Count)
Add-Check 'AI dirs in pool' ($aiPools.Count -eq 0) ("count={0}" -f $aiPools.Count)
Add-Check 'AI dirs in %TEMP%\wps' ($aiTemps.Count -eq 0) ("count={0}" -f $aiTemps.Count)

$mods = @(Get-WpsAiModuleReport)
Add-Check 'No AI DLLs loaded' ($mods.Count -eq 0) (($mods | Select-Object -First 3) -join '; ')

$key = 'HKCU:\Software\Kingsoft\Office\6.0\Common\ResourceManager\setupPluginUpdate'
$flagCount = 0
if (Test-Path $key) {
  $flagCount = ((Get-ItemProperty $key).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -match $script:WpsAiFlagRegex } | Measure-Object).Count
}
Add-Check 'setupPluginUpdate AI flags' ($flagCount -eq 0) ("count={0}" -f $flagCount)

$tokenCount = 0
$ak = 'HKCU:\Software\Kingsoft\Office\6.0\plugins\kappmgr'
if (Test-Path $ak) {
  $v = (Get-ItemProperty $ak -Name CloudSvrAppList -ErrorAction SilentlyContinue).CloudSvrAppList
  if ($v) { $tokenCount = ([regex]::Matches($v, $script:WpsAiFlagRegex)).Count }
}
Add-Check 'CloudSvrAppList AI tokens' ($tokenCount -eq 0) ("count={0}" -f $tokenCount)

$keyCount = 0
$pk = 'HKCU:\Software\Kingsoft\Office\6.0\plugins'
if (Test-Path $pk) { $keyCount = (Get-ChildItem $pk | Where-Object { $_.PSChildName -match $script:WpsAiNameRegex } | Measure-Object).Count }
Add-Check 'AI plugin registry keys' ($keyCount -eq 0) ("count={0}" -f $keyCount)

$configTotal = 0
foreach ($r in $roots) {
  $plg = Join-Path $r 'office6\setupplugincfg\setupplugin.plg'
  $applist = Join-Path $r 'office6\addons\kapplist\applist.xml'
  $crc = Join-Path $r 'utility\crcmap.dat'
  $ifl = Join-Path $r 'utility\installfilelist.dat'
  if (Test-Path $plg) { $configTotal += (Get-WpsFileAiCount $plg 'UTF8') }
  if (Test-Path $applist) { $configTotal += (Get-WpsFileAiCount $applist 'UTF8') }
  if (Test-Path $crc) { $configTotal += (Get-WpsFileAiCount $crc 'Unicode') }
  if (Test-Path $ifl) { $configTotal += (Get-WpsFileAiCount $ifl 'Legacy') }
}
foreach ($p in $pools) {
  Get-ChildItem $p -Directory -Filter 'kapplist_*' -ErrorAction SilentlyContinue | ForEach-Object {
    $f = Join-Path $_.FullName 'applist.xml'
    if (Test-Path $f) { $configTotal += (Get-WpsFileAiCount $f 'UTF8') }
  }
}
Add-Check 'AI refs in config/manifests' ($configTotal -eq 0) ("count={0}" -f $configTotal)

$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
$hostsOk = $false; $unrelatedOk = $false
if (Test-Path $hosts) {
  $h = Get-Content $hosts -Raw -ErrorAction SilentlyContinue
  $hostsOk = $h -match 'BEGIN WPS AI / UPDATE BLOCK'
  $unrelatedOk = @($h -split "`r?`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*0\.0\.0\.0\s' }).Count -gt 0
}
Add-Check 'Hosts WPS block' $hostsOk
Add-Check 'Hosts unrelated entries preserved' $unrelatedOk

$fw = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'WPSAI_Block_*' })
Add-Check 'Firewall WPSAI_Block_* rules' ($fw.Count -gt 0) ("count={0}" -f $fw.Count)

$tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match '^(WpsUpdateTask|WpsUpdateLogonTask|WpsWakeWnsLogonTask)' })
$tasksOk = $true
foreach ($t in $tasks) { if ($t.State -ne 'Disabled') { $tasksOk = $false } }
Add-Check 'WPS update tasks absent or disabled' $tasksOk ("count={0}" -f $tasks.Count)

$aclOk = $true; $aclDetail = @()
foreach ($d in @($addonRoots + $pools)) {
  $denied = Test-WpsCreateDenied $d
  if ($denied -ne $true) { $aclOk = $false }
  $aclDetail += ("{0}:{1}" -f $d, $denied)
}
Add-Check 'Addon/pool create denied' $aclOk ($aclDetail -join ' | ')

$guard = Get-ScheduledTask -TaskName 'WPSAI_Guard' -ErrorAction SilentlyContinue
Add-Check 'Guard task present' ($null -ne $guard) ($(if ($guard) { $guard.State } else { 'missing' }))
$guardLog = 'C:\ProgramData\WPSAI_Guard\guard.log'
Add-Check 'Guard log exists' (Test-Path $guardLog) $guardLog

$procs = @(Get-WpsProcesses)
if ($procs.Count -gt 0) {
  $resp = ($procs | Where-Object { -not $_.Responding }).Count -eq 0
  Write-WpsLog ("INFO  WPS processes: {0}; all responding: {1}" -f $procs.Count, $resp)
} else {
  Write-WpsLog 'INFO  WPS is not running.'
}

Write-WpsLog ("=== VERIFY SUMMARY pass={0} fail={1} ===" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
