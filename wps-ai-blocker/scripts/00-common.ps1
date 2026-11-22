# Shared helpers for wps-ai-blocker.
# Dot-source from other scripts: . "$PSScriptRoot\00-common.ps1"

$ErrorActionPreference = 'Stop'

$script:WpsAiNameRegex = '(?i)^(kaiwpp|kcopilot|ketai|ketcopilot|kpdfai|kpdfcopilot|kpubaigcbox|ktaskpanelcopilot|kwebaireport|kwebwpscopilot|kwebaipdfinsight|kwebaihistory|kwebwpsdoccomposing|kwebwpsinstructioncenter|kwebwpsainewfilepanel|kwebwppaioutline|kwebwpsairesources|kwebaitoolbarskillbuilder|kwebwpsmathor|kwppai|kwppcopilot|kwpsai|kwpscopilot|karticlewebcloudsummary|kwpsthesisassistant|kwpsailingxi)'
$script:WpsAiLineRegex = '(?i)(kaiwpp|kcopilot|ketai|ketcopilot|kpdfai|kpdfcopilot|kpubaigcbox|ktaskpanelcopilot|kwebaireport|kwebwpscopilot|kwebaipdfinsight|kwebaihistory|kwebwpsdoccomposing|kwebwpsinstructioncenter|kwebwpsainewfilepanel|kwebwppaioutline|kwebwpsairesources|kwebaitoolbarskillbuilder|kwebwpsmathor|kwppai|kwppcopilot|kwpsai|kwpscopilot|karticlewebcloudsummary|kwpsthesisassistant|kwpsailingxi)'
$script:WpsAiFlagRegex = '(?i)(copilot|kwpsai|kwppai|ketai|kpdfai|aigc|kaiwpp|kwppcopilot|kpubaigcbox|karticlewebcloudsummary|kwpsthesisassistant)'
$script:WpsAiDomains = @(
  'abp.wps.cn','365.kdocs.cn','wpscdn.cn','down.wps.cn','dl.wps.cn','update.wps.cn','wpsupdate.wps.cn',
  'update.wpscdn.cn','ks3-cn-beijing.ksyun.com','dldir1.qq.com',
  'pc-update-1.wpscdn.cn','pc-update-2.wpscdn.cn','pc-update-3.wpscdn.cn','pc-update-4.wpscdn.cn','pc-update-5.wpscdn.cn',
  'pc-update-6.wpscdn.cn','pc-update-7.wpscdn.cn','pc-update-8.wpscdn.cn','pc-update-9.wpscdn.cn','pc-update-10.wpscdn.cn'
)
$script:DefaultQuarantine = 'C:\WPSAI_Disabled'
$script:LogPath = $null

function Initialize-WpsAiLog {
  param([string]$Name = 'session')
  $dir = Join-Path $env:TEMP 'wps-ai-blocker'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $script:LogPath = Join-Path $dir ("{0}-{1}.log" -f $Name, (Get-Date -Format 'yyyyMMdd_HHmmss'))
  Write-WpsLog "Log: $script:LogPath"
}

function Write-WpsLog {
  param([string]$Message, [ValidateSet('INFO','WARN','ERROR','PASS','FAIL')][string]$Level = 'INFO')
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Write-Host $line
  if ($script:LogPath) {
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
  }
}

function Test-IsAdmin {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Ensure-Elevated {
  param([string]$ScriptPath, [string[]]$Arguments = @())
  if (Test-IsAdmin) { return }
  $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$ScriptPath`"") + $Arguments
  Write-WpsLog 'Requesting administrator elevation (UAC)...' 'WARN'
  Start-Process powershell -Verb RunAs -ArgumentList $argList
  exit 0
}

function Get-WpsProcesses {
  Get-Process -Name wps,wpp,et,pdf,wpsoffice,ksolaunch -ErrorAction SilentlyContinue
}

function Get-WpsInstallRoots {
  param([string]$InstallRoot)
  if ($InstallRoot) {
    if (Test-Path (Join-Path $InstallRoot 'office6')) { return @((Resolve-Path $InstallRoot).Path) }
    Write-WpsLog "Provided -InstallRoot does not contain office6: $InstallRoot" 'WARN'
    return @()
  }
  $roots = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

  foreach ($p in (Get-WpsProcesses)) {
    if ($p.Path) {
      $dir = Split-Path $p.Path -Parent
      if ((Split-Path $dir -Leaf) -ieq 'office6') { [void]$roots.Add((Split-Path $dir -Parent)) }
      elseif (Test-Path (Join-Path $dir 'office6')) { [void]$roots.Add($dir) }
    }
  }

  # Registry InstallRoot is the most reliable clue (including non-system drives).
  foreach ($k in @(
    'HKCU:\Software\Kingsoft\Office\6.0\Common',
    'HKLM:\Software\Kingsoft\Office\6.0\Common',
    'HKLM:\Software\WOW6432Node\Kingsoft\Office\6.0\Common'
  )) {
    if (Test-Path $k) {
      $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
      if ($p.InstallRoot -and (Test-Path (Join-Path $p.InstallRoot 'office6'))) {
        [void]$roots.Add($p.InstallRoot)
      }
    }
  }

  # Uninstall entries: InstallLocation, DisplayIcon, UninstallString.
  $uninstallRoots = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach ($u in $uninstallRoots) {
    Get-ChildItem $u -ErrorAction SilentlyContinue | ForEach-Object {
      $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
      if ($p -and $p.DisplayName -match '(?i)WPS Office|Kingsoft') {
        if ($p.InstallLocation -and (Test-Path (Join-Path $p.InstallLocation 'office6'))) {
          [void]$roots.Add($p.InstallLocation)
        }
        if ($p.DisplayIcon) {
          $icon = ($p.DisplayIcon -replace '"','').Trim()
          if (Test-Path $icon) {
            $dir = Split-Path $icon -Parent
            if ((Split-Path $dir -Leaf) -ieq 'office6') { [void]$roots.Add((Split-Path $dir -Parent)) }
            elseif (Test-Path (Join-Path $dir 'office6')) { [void]$roots.Add($dir) }
          }
        }
        if ($p.UninstallString) {
          $us = ($p.UninstallString -replace '"','').Trim()
          if ($us -match '^(.*?)\\utility\\') {
            $candidate = $Matches[1]
            if (Test-Path (Join-Path $candidate 'office6')) { [void]$roots.Add($candidate) }
          }
        }
      }
    }
  }

  # Scheduled update tasks point at ksolaunch.exe in the install parent.
  Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match '^(WpsUpdateTask|WpsUpdateLogonTask|WpsWakeWnsLogonTask)' } | ForEach-Object {
    $_.Actions | ForEach-Object {
      $exe = ($_.Execute -replace '"','').Trim()
      if ($exe -and (Test-Path $exe)) {
        $dir = Split-Path $exe -Parent
        if (Test-Path (Join-Path $dir 'office6')) { [void]$roots.Add($dir) }
        Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
          if (Test-Path (Join-Path $_.FullName 'office6')) { [void]$roots.Add($_.FullName) }
        }
      }
    }
  }

  $common = @()
  $pf = $env:ProgramFiles
  $pf86 = ${env:ProgramFiles(x86)}
  if ($env:ProgramFiles) { $common += (Join-Path $env:ProgramFiles 'WPS Office') }
  if ($pf86) { $common += (Join-Path $pf86 'WPS Office') }
  if ($env:ProgramFiles) { $common += (Join-Path $env:ProgramFiles 'Kingsoft\WPS Office') }
  if ($pf86) { $common += (Join-Path $pf86 'Kingsoft\WPS Office') }
  $common += (Join-Path $env:LOCALAPPDATA 'Kingsoft\WPS Office')
  foreach ($c in $common) {
    if (-not $c -or -not (Test-Path $c)) { continue }
    if (Test-Path (Join-Path $c 'office6')) { [void]$roots.Add($c) }
    Get-ChildItem $c -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      if (Test-Path (Join-Path $_.FullName 'office6')) { [void]$roots.Add($_.FullName) }
      Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-Path (Join-Path $_.FullName 'office6')) { [void]$roots.Add($_.FullName) }
      }
    }
  }

  return @($roots | Where-Object { Test-Path (Join-Path $_ 'office6') } | Sort-Object)
}

function Get-WpsPoolRoots {
  $result = @()
  foreach ($base in @(
    (Join-Path $env:APPDATA 'kingsoft\wps\addons\pool'),
    (Join-Path $env:LOCALAPPDATA 'Kingsoft\WPS Office\addons\pool')
  )) {
    if (Test-Path $base) {
      $result += Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^win-' } | Select-Object -ExpandProperty FullName
    }
  }
  return @($result | Sort-Object -Unique)
}

function Get-WpsTempRoots {
  $result = @()
  foreach ($p in @((Join-Path $env:TEMP 'wps'), (Join-Path $env:TEMP 'WPS'))) {
    if (Test-Path $p) { $result += (Resolve-Path $p).Path }
  }
  return @($result | Sort-Object -Unique)
}

function Get-WpsAddonRoots {
  param([string[]]$InstallRoots = (Get-WpsInstallRoots))
  foreach ($r in $InstallRoots) {
    $a = Join-Path $r 'office6\addons'
    if (Test-Path $a) { $a }
  }
}

function Test-WpsAiName {
  param([string]$Name)
  return ($Name -match $script:WpsAiNameRegex)
}

function Get-WpsAiDirectories {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return @() }
  Get-ChildItem $Path -Directory -ErrorAction SilentlyContinue | Where-Object { Test-WpsAiName $_.Name }
}

function Backup-WpsFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  $bak = $Path + '.wpsai_bak_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
  Copy-Item -LiteralPath $Path -Destination $bak -Force
  return $bak
}

function Clear-WpsReadOnly {
  param([string]$Path)
  if (Test-Path $Path) { Set-ItemProperty -LiteralPath $Path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue }
}

function Set-WpsReadOnly {
  param([string]$Path)
  if (Test-Path $Path) { Set-ItemProperty -LiteralPath $Path -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue }
}

function Move-WpsAiDirectories {
  param(
    [string]$Source,
    [string]$Destination,
    [switch]$WhatIf
  )
  $moved = 0; $failed = 0
  if (-not (Test-Path $Source)) { return [pscustomobject]@{Moved=0;Failed=0} }
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($d in (Get-WpsAiDirectories $Source)) {
    $dest = Join-Path $Destination $d.Name
    if (Test-Path $dest) { $dest = $dest + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
    if ($WhatIf) {
      Write-WpsLog "WHATIF move $($d.FullName) -> $dest"
      $moved++
      continue
    }
    try {
      Move-Item -LiteralPath $d.FullName -Destination $dest -Force -ErrorAction Stop
      Write-WpsLog "MOVED $($d.FullName) -> $dest"
      $moved++
    } catch {
      Write-WpsLog "FAILED move $($d.FullName): $($_.Exception.Message)" 'WARN'
      $failed++
    }
  }
  return [pscustomobject]@{Moved=$moved;Failed=$failed}
}

function Remove-WpsAiRegistry {
  param([switch]$WhatIf)
  $removed = 0
  $key = 'HKCU:\Software\Kingsoft\Office\6.0\Common\ResourceManager\setupPluginUpdate'
  if (Test-Path $key) {
    $props = (Get-ItemProperty $key -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -notmatch '^PS' -and $_.Name -match $script:WpsAiFlagRegex }
    foreach ($p in $props) {
      if ($WhatIf) { Write-WpsLog "WHATIF remove setupPluginUpdate value $($p.Name)" }
      else { Remove-ItemProperty -Path $key -Name $p.Name -Force -ErrorAction SilentlyContinue; Write-WpsLog "REMOVED setupPluginUpdate value $($p.Name)" }
      $removed++
    }
  }

  $ak = 'HKCU:\Software\Kingsoft\Office\6.0\plugins\kappmgr'
  if (Test-Path $ak) {
    $v = (Get-ItemProperty $ak -Name CloudSvrAppList -ErrorAction SilentlyContinue).CloudSvrAppList
    if ($v) {
      $parts = $v -split ','
      $kept = $parts | Where-Object { $_ -notmatch $script:WpsAiFlagRegex }
      if ($kept.Count -ne $parts.Count) {
        if (-not $WhatIf) { Set-ItemProperty -Path $ak -Name CloudSvrAppList -Value ($kept -join ',') -ErrorAction SilentlyContinue }
        Write-WpsLog ("CloudSvrAppList: removed {0} AI tokens" -f ($parts.Count - $kept.Count))
        $removed += ($parts.Count - $kept.Count)
      }
    }
  }

  $pk = 'HKCU:\Software\Kingsoft\Office\6.0\plugins'
  if (Test-Path $pk) {
    Get-ChildItem $pk -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $script:WpsAiNameRegex } | ForEach-Object {
      if ($WhatIf) { Write-WpsLog "WHATIF remove plugin key $($_.PSChildName)" }
      else { Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue; Write-WpsLog "REMOVED plugin key $($_.PSChildName)" }
      $removed++
    }
  }

  $seq = 'HKCU:\Software\Kingsoft\Office\6.0\plugins\kstartpage\officenav_new_v1\seqEntry\CommonEntrys'
  foreach ($n in @('wpsaiassistant','wpsaippt')) {
    if (Test-Path $seq) {
      $exists = (Get-ItemProperty $seq -Name $n -ErrorAction SilentlyContinue) -ne $null
      if ($exists) {
        if ($WhatIf) { Write-WpsLog "WHATIF remove startpage value $n" }
        else { Remove-ItemProperty -Path $seq -Name $n -Force -ErrorAction SilentlyContinue; Write-WpsLog "REMOVED startpage value $n" }
        $removed++
      }
    }
  }
  return $removed
}

function Remove-WpsAiLinesFromTextFile {
  param(
    [string]$Path,
    [ValidateSet('UTF8','Unicode')][string]$Encoding = 'UTF8',
    [string]$LineSeparator = "`r`n",
    [string]$Pattern = $script:WpsAiLineRegex,
    [switch]$WhatIf
  )
  if (-not (Test-Path $Path)) { return 0 }
  $bak = Backup-WpsFile $Path
  Clear-WpsReadOnly $Path
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $text = if ($Encoding -eq 'Unicode') { [System.Text.Encoding]::Unicode.GetString($bytes) } else { [System.Text.Encoding]::UTF8.GetString($bytes) }
  $lines = $text -split [regex]::Escape($LineSeparator)
  $kept = @($lines | Where-Object { $_ -notmatch $Pattern })
  $removed = $lines.Count - $kept.Count
  if (-not $WhatIf) {
    $newText = $kept -join $LineSeparator
    $out = if ($Encoding -eq 'Unicode') { [System.Text.Encoding]::Unicode.GetBytes($newText) } else { (New-Object System.Text.UTF8Encoding($false)).GetBytes($newText) }
    [System.IO.File]::WriteAllBytes($Path, $out)
    Set-WpsReadOnly $Path
  }
  Write-WpsLog ("{0}: removed {1} lines (backup {2})" -f $Path, $removed, $bak)
  return $removed
}

function Remove-WpsAiLinesFromManifest {
  param(
    [string]$Path,
    [ValidateSet('Unicode','Legacy')][string]$Encoding = 'Unicode',
    [switch]$WhatIf
  )
  if (-not (Test-Path $Path)) { return 0 }
  $bak = Backup-WpsFile $Path
  Clear-WpsReadOnly $Path
  $raw = [System.IO.File]::ReadAllBytes($Path)
  if ($Encoding -eq 'Unicode') {
    $bom = $raw.Length -ge 2 -and $raw[0] -eq 0xFF -and $raw[1] -eq 0xFE
    $body = if ($bom -and $raw.Length -gt 2) { [byte[]]$raw[2..($raw.Length-1)] } else { $raw }
    $sep = [byte[]](0x0D,0x00,0x0A,0x00)
    # Split on CRLF in UTF-16LE without decoding the whole file.
    $parts = [System.Collections.Generic.List[byte[]]]::new()
    $start = 0
    for ($i = 0; $i -le $body.Length - 4; $i++) {
      if ($body[$i] -eq 0x0D -and $body[$i+1] -eq 0x00 -and $body[$i+2] -eq 0x0A -and $body[$i+3] -eq 0x00) {
        $len = $i - $start
        $seg = [byte[]]::new($len)
        [Array]::Copy($body, $start, $seg, 0, $len)
        $parts.Add($seg)
        $i += 3
        $start = $i + 1
      }
    }
    if ($start -lt $body.Length) {
      $len = $body.Length - $start
      $seg = [byte[]]::new($len)
      [Array]::Copy($body, $start, $seg, 0, $len)
      $parts.Add($seg)
    }
    $kept = [System.Collections.Generic.List[byte[]]]::new()
    $removed = 0
    foreach ($p in $parts) {
      $s = [System.Text.Encoding]::Unicode.GetString($p)
      if ($s -match $script:WpsAiLineRegex) { $removed++; continue }
      $kept.Add($p)
    }
    if (-not $WhatIf) {
      $out = [System.Collections.Generic.List[byte]]::new()
      if ($bom) { $out.Add(0xFF); $out.Add(0xFE) }
      for ($j = 0; $j -lt $kept.Count; $j++) {
        $out.AddRange($kept[$j])
        if ($j -lt $kept.Count - 1) { $out.AddRange($sep) }
      }
      [System.IO.File]::WriteAllBytes($Path, $out.ToArray())
      Set-WpsReadOnly $Path
    }
  } else {
    $sep = [byte[]](0x0D,0x0A)
    $parts = [System.Collections.Generic.List[byte[]]]::new()
    $start = 0
    for ($i = 0; $i -le $raw.Length - 2; $i++) {
      if ($raw[$i] -eq 0x0D -and $raw[$i+1] -eq 0x0A) {
        $len = $i - $start
        $seg = [byte[]]::new($len)
        [Array]::Copy($raw, $start, $seg, 0, $len)
        $parts.Add($seg)
        $i += 1
        $start = $i + 1
      }
    }
    if ($start -lt $raw.Length) {
      $len = $raw.Length - $start
      $seg = [byte[]]::new($len)
      [Array]::Copy($raw, $start, $seg, 0, $len)
      $parts.Add($seg)
    }
    $kept = [System.Collections.Generic.List[byte[]]]::new()
    $removed = 0
    foreach ($p in $parts) {
      $s = [System.Text.Encoding]::GetEncoding(28591).GetString($p)
      if ($s -match $script:WpsAiLineRegex) { $removed++; continue }
      $kept.Add($p)
    }
    if (-not $WhatIf) {
      $out = [System.Collections.Generic.List[byte]]::new()
      for ($j = 0; $j -lt $kept.Count; $j++) {
        $out.AddRange($kept[$j])
        if ($j -lt $kept.Count - 1) { $out.AddRange($sep) }
      }
      [System.IO.File]::WriteAllBytes($Path, $out.ToArray())
      Set-WpsReadOnly $Path
    }
  }
  Write-WpsLog ("{0}: removed {1} lines (backup {2})" -f $Path, $removed, $bak)
  return $removed
}

function Test-WpsCreateDenied {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  $test = Join-Path $Path '__wpsai_acl_test__'
  New-Item -ItemType Directory -Path $test -ErrorAction SilentlyContinue | Out-Null
  $ok = -not (Test-Path $test)
  if (Test-Path $test) { Remove-Item -LiteralPath $test -Recurse -Force -ErrorAction SilentlyContinue }
  return $ok
}

function Get-WpsAiModuleReport {
  $cmd = @'
$ErrorActionPreference = "SilentlyContinue"
Get-Process wps -ErrorAction SilentlyContinue | ForEach-Object {
  $p = $_
  $p.Modules | Where-Object { $_.ModuleName -match 'kwpsai|copilot|aigc|kwppai|kpdfai|ketai|lingxi|klingxidockpanel' } |
    ForEach-Object { "{0}`t{1}`t{2}" -f $p.Id, $_.ModuleName, $_.FileName }
}
'@
  $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  $out = & "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -EncodedCommand $b64 2>$null
  return @($out | Where-Object { $_ })
}

function Get-WpsFileAiCount {
  param([string]$Path, [ValidateSet('UTF8','Unicode','Legacy')][string]$Encoding = 'UTF8')
  if (-not (Test-Path $Path)) { return 0 }
  $raw = [System.IO.File]::ReadAllBytes($Path)
  if ($Encoding -eq 'Unicode') { $s = [System.Text.Encoding]::Unicode.GetString($raw) }
  elseif ($Encoding -eq 'Legacy') { $s = [System.Text.Encoding]::GetEncoding(28591).GetString($raw) }
  else { $s = [System.Text.Encoding]::UTF8.GetString($raw) }
  return ([regex]::Matches($s, $script:WpsAiLineRegex)).Count
}
