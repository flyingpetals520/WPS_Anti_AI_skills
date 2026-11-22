$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\00-common.ps1"
$script:LogPath = Join-Path $PSScriptRoot 'guard.log'
$quarantine = 'C:\WPSAI_Disabled'
$installDst = Join-Path $quarantine 'install'
$poolDst = Join-Path $quarantine 'pool'
$tempDst = Join-Path $quarantine 'temp'
foreach ($d in @($installDst,$poolDst,$tempDst)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

$roots = @(Get-WpsInstallRoots)
$pools = @(Get-WpsPoolRoots)
$temps = @(Get-WpsTempRoots)

foreach ($a in @(Get-WpsAddonRoots -InstallRoots $roots)) {
  Move-WpsAiDirectories -Source $a -Destination $installDst | Out-Null
}
foreach ($p in $pools) {
  Move-WpsAiDirectories -Source $p -Destination $poolDst | Out-Null
}
foreach ($t in $temps) {
  Move-WpsAiDirectories -Source $t -Destination $tempDst | Out-Null
}

# Legacy in-tree quarantine folders must be emptied and removed.
foreach ($r in $roots) {
  $legacy = Join-Path $r 'office6\addons_wpsai_disabled'
  if (Test-Path $legacy) {
    Move-WpsAiDirectories -Source $legacy -Destination $installDst | Out-Null
    Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
  }
}
foreach ($p in $pools) {
  $parent = Split-Path $p -Parent
  Get-ChildItem $parent -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '_wpsai_disabled$' } | ForEach-Object {
    Move-WpsAiDirectories -Source $_.FullName -Destination $poolDst | Out-Null
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Remove-WpsAiRegistry | Out-Null

# Catch WPS update/wake tasks for any user suffix.
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match '^(WpsUpdateTask|WpsUpdateLogonTask|WpsWakeWnsLogonTask)' } | ForEach-Object {
  Disable-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue | Out-Null
}

# Ensure hosts block exists.
$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
if (Test-Path $hosts) {
  $txt = Get-Content -LiteralPath $hosts -Raw -ErrorAction SilentlyContinue
  if ($txt -notmatch 'BEGIN WPS AI / UPDATE BLOCK') {
    $filtered = Get-Content -LiteralPath $hosts -ErrorAction SilentlyContinue | Where-Object {
      $line = $_
      -not ($script:WpsAiDomains | Where-Object { $line -match [regex]::Escape($_) }) -and
      $line -notmatch '^#\s*(BEGIN|END) WPS AI / UPDATE BLOCK'
    }
    $block = @('# BEGIN WPS AI / UPDATE BLOCK')
    foreach ($d in $script:WpsAiDomains) { $block += ('0.0.0.0 ' + $d) }
    $block += '# END WPS AI / UPDATE BLOCK'
    $tmp = Join-Path $env:TEMP 'hosts_wps_ai_guard.txt'
    Set-Content -LiteralPath $tmp -Value (@($filtered) + $block) -Encoding ASCII -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $tmp -Destination $hosts -Force -ErrorAction SilentlyContinue
  }
}

# Re-apply the deny ACL (guard runs with highest privileges).
$user = "$env:USERDOMAIN\$env:USERNAME"
foreach ($dir in @(@(Get-WpsAddonRoots -InstallRoots $roots) + $pools)) {
  if (Test-Path $dir) { & icacls $dir /deny "${user}:(AD,WD)" 2>$null | Out-Null }
}

Add-Content -Path $script:LogPath -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' checked') -ErrorAction SilentlyContinue
