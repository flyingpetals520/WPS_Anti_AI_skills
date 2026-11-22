param(
  [string]$InstallRoot,
  [string]$QuarantineRoot = 'C:\WPSAI_Disabled'
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name 'recon'

Write-WpsLog '=== WPS AI BLOCKER RECON ==='
Write-WpsLog ("Admin: {0}" -f (Test-IsAdmin))
Write-WpsLog ("Computer: {0}  User: {1}\{2}" -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME)

$roots = @(Get-WpsInstallRoots -InstallRoot $InstallRoot)
Write-WpsLog ("Install roots: {0}" -f ($roots -join '; '))

foreach ($r in $roots) {
  $office = Join-Path $r 'office6'
  Write-WpsLog "--- Install root: $r"
  Get-ChildItem $office -Filter 'wps.exe' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-WpsLog ("  wps.exe: {0} ({1})" -f $_.FullName, $_.VersionInfo.FileVersion)
  }
  $addons = Join-Path $office 'addons'
  $ai = @(Get-WpsAiDirectories $addons)
  $aiNames = @($ai | ForEach-Object { $_.Name }) -join ', '
  Write-WpsLog ("  AI addon dirs: {0}" -f $aiNames)
  Write-WpsLog ("  addons create denied: {0}" -f (Test-WpsCreateDenied $addons))

  $plg = Join-Path $office 'setupplugincfg\setupplugin.plg'
  $applist = Join-Path $office 'addons\kapplist\applist.xml'
  $crc = Join-Path $r 'utility\crcmap.dat'
  $ifl = Join-Path $r 'utility\installfilelist.dat'
  foreach ($f in @($plg,$applist,$crc,$ifl)) {
    if (Test-Path $f) {
      $enc = if ($f -eq $crc) { 'Unicode' } elseif ($f -eq $ifl) { 'Legacy' } else { 'UTF8' }
      Write-WpsLog ("  {0}: AI refs={1} readonly={2}" -f $f, (Get-WpsFileAiCount $f $enc), (Get-Item $f).IsReadOnly)
    } else {
      Write-WpsLog ("  missing: {0}" -f $f)
    }
  }
}

$pools = @(Get-WpsPoolRoots)
Write-WpsLog ("Pool roots: {0}" -f ($pools -join '; '))
foreach ($p in $pools) {
  $ai = @(Get-WpsAiDirectories $p)
  $poolAiNames = @($ai | ForEach-Object { $_.Name }) -join ', '
  Write-WpsLog ("--- {0}: AI dirs={1}, create denied={2}" -f $p, $poolAiNames, (Test-WpsCreateDenied $p))
  Get-ChildItem $p -Directory -Filter 'kapplist_*' -ErrorAction SilentlyContinue | ForEach-Object {
    $f = Join-Path $_.FullName 'applist.xml'
    if (Test-Path $f) { Write-WpsLog ("  {0}: AI refs={1}" -f $f, (Get-WpsFileAiCount $f 'UTF8')) }
  }
}

$temps = @(Get-WpsTempRoots)
Write-WpsLog ("Temp roots: {0}" -f ($temps -join '; '))
foreach ($t in $temps) {
  $ai = @(Get-WpsAiDirectories $t)
  $tempAiNames = @($ai | ForEach-Object { $_.Name }) -join ', '
  Write-WpsLog ("--- {0}: AI dirs={1}" -f $t, $tempAiNames)
}

Write-WpsLog '--- Running WPS processes ---'
Get-WpsProcesses | ForEach-Object {
  Write-WpsLog ("  PID {0} {1} {2} MB responding={3}" -f $_.Id, $_.ProcessName, [math]::Round($_.WorkingSet64/1MB,1), $_.Responding)
}
$mods = @(Get-WpsAiModuleReport)
Write-WpsLog ("Loaded AI modules: {0}" -f (($mods -join '; ')))

Write-WpsLog '--- Registry ---'
$key = 'HKCU:\Software\Kingsoft\Office\6.0\Common\ResourceManager\setupPluginUpdate'
$flagCount = 0
if (Test-Path $key) {
  $flagCount = ((Get-ItemProperty $key).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -match $script:WpsAiFlagRegex } | Measure-Object).Count
}
Write-WpsLog ("setupPluginUpdate AI flags: {0}" -f $flagCount)
$tokenCount = 0
$ak = 'HKCU:\Software\Kingsoft\Office\6.0\plugins\kappmgr'
if (Test-Path $ak) {
  $v = (Get-ItemProperty $ak -Name CloudSvrAppList -ErrorAction SilentlyContinue).CloudSvrAppList
  if ($v) { $tokenCount = ([regex]::Matches($v, $script:WpsAiFlagRegex)).Count }
}
Write-WpsLog ("CloudSvrAppList AI tokens: {0}" -f $tokenCount)
$pk = 'HKCU:\Software\Kingsoft\Office\6.0\plugins'
$keyCount = 0
if (Test-Path $pk) { $keyCount = (Get-ChildItem $pk | Where-Object { $_.PSChildName -match $script:WpsAiNameRegex } | Measure-Object).Count }
Write-WpsLog ("AI plugin keys: {0}" -f $keyCount)

Write-WpsLog '--- Network / tasks / guard ---'
$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
if (Test-Path $hosts) {
  $h = Get-Content $hosts -Raw -ErrorAction SilentlyContinue
  $unrelated = @($h -split "`r?`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*0\.0\.0\.0\s' }).Count
  Write-WpsLog ("hosts: block={0} unrelated={1} domains={2} size={3}" -f ($h -match 'BEGIN WPS AI / UPDATE BLOCK'), $unrelated, ([regex]::Matches($h,'(?m)^0\.0\.0\.0 ')).Count, (Get-Item $hosts).Length)
}
$fw = @(Get-NetFirewallRule -DisplayName 'WPSAI_Block_*' -ErrorAction SilentlyContinue)
Write-WpsLog ("Firewall WPSAI_Block_* rules: {0}" -f $fw.Count)
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'WpsUpdate|WpsWake' } |
  ForEach-Object { Write-WpsLog ("Task: {0} = {1}" -f $_.TaskName, $_.State) }
$guard = Get-ScheduledTask -TaskName 'WPSAI_Guard' -ErrorAction SilentlyContinue
Write-WpsLog ("Guard task: {0}" -f ($(if ($guard) { $guard.State } else { 'missing' })))
if (Test-Path 'C:\ProgramData\WPSAI_Guard\guard.log') {
  Write-WpsLog ("Guard log tail: {0}" -f ((Get-Content 'C:\ProgramData\WPSAI_Guard\guard.log' -Tail 3) -join ' | '))
}

Write-WpsLog '--- Quarantine ---'
if (Test-Path $QuarantineRoot) {
  Get-ChildItem $QuarantineRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $count = (Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-WpsLog ("  {0}: {1} dirs" -f $_.FullName, $count)
  }
} else {
  Write-WpsLog ("  {0} does not exist" -f $QuarantineRoot)
}

Write-WpsLog '=== RECON COMPLETE ==='

exit 0
