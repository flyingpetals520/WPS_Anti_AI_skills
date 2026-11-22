# Verification

Run the automated check first:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\99-verify.ps1
```

It prints `PASS`/`FAIL` for each layer and exits non-zero if anything fails.

## Manual checklist

### 1. No AI directories in the WPS tree

```powershell
$ai = '(?i)^(kaiwpp|kcopilot|ketai|ketcopilot|kpdfai|kpdfcopilot|kpubaigcbox|ktaskpanelcopilot|kwebaireport|kwebwpscopilot|kwebaipdfinsight|kwebaihistory|kwebwpsdoccomposing|kwebwpsinstructioncenter|kwebwpsainewfilepanel|kwebwppaioutline|kwebwpsairesources|kwebaitoolbarskillbuilder|kwebwpsmathor|kwppai|kwppcopilot|kwpsai|kwpscopilot|karticlewebcloudsummary|kwpsthesisassistant|kwpsailingxi)'
Get-ChildItem "<install-root>\office6\addons" -Directory |
  Where-Object Name -match $ai
Get-ChildItem "$env:APPDATA\kingsoft\wps\addons\pool" -Directory -Recurse -Depth 2 |
  Where-Object Name -match $ai
Get-ChildItem "$env:TEMP\wps" -Directory |
  Where-Object Name -match $ai
```

All three must return nothing.

### 2. No AI modules loaded (32-bit)

```powershell
& "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command {
  Get-Process wps -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_
    $p.Modules | Where-Object { $_.ModuleName -match 'kwpsai|copilot|aigc|kwppai|kpdfai|ketai|lingxi|klingxidockpanel' } |
      ForEach-Object { "{0}`t{1}`t{2}" -f $p.Id, $_.ModuleName, $_.FileName }
  }
}
```

Must return nothing.

### 3. Registry clean

```powershell
# AI values under setupPluginUpdate
$key = 'HKCU:\Software\Kingsoft\Office\6.0\Common\ResourceManager\setupPluginUpdate'
(Get-ItemProperty $key).PSObject.Properties |
  Where-Object { $_.Name -notmatch '^PS' -and $_.Name -match '(?i)(copilot|kwpsai|kwppai|ketai|kpdfai|aigc|kaiwpp)' }

# AI tokens in CloudSvrAppList
$v = (Get-ItemProperty 'HKCU:\Software\Kingsoft\Office\6.0\plugins\kappmgr' -Name CloudSvrAppList).CloudSvrAppList
[regex]::Matches($v, '(?i)(copilot|kwpsai|kwppai|ketai|kpdfai|aigc|ai_space|aivideo|AiSmartOrganize)').Count

# AI plugin keys
Get-ChildItem 'HKCU:\Software\Kingsoft\Office\6.0\plugins' |
  Where-Object { $_.PSChildName -match '(?i)(copilot|kwpsai|kwppai|ketai|kpdfai|aigc|kaiwpp)' }
```

All must be empty/0.

### 4. Config files clean

- `setupplugin.plg`: no `kwpsai`/`kcopilot`/`klingxidockpanel`/`kwpslingxi` names.
- `applist.xml` (install and pool `kapplist_*`): no AI app entries.
- `crcmap.dat` (UTF-16LE) and `installfilelist.dat` (byte-wise): no AI paths.

The scripts write `.wpsai_bak_<timestamp>` next to each edited file.

### 5. Network block

```powershell
Select-String "$env:WINDIR\System32\drivers\etc\hosts" -Pattern 'BEGIN WPS AI / UPDATE BLOCK'
netsh advfirewall firewall show rule name=all | Select-String 'WPSAI_Block_'
schtasks /Query /FO LIST | Select-String 'WpsUpdate'
```

- Hosts block present (20 domains).
- Firewall rules present (at least the update executables; 50 rules in the reference run).
- WPS update tasks absent or disabled.

### 6. ACL lock

```powershell
$dirs = @(
  "<install-root>\office6\addons",
  "$env:APPDATA\kingsoft\wps\addons\pool\win-i386"
)
foreach ($d in $dirs) {
  $test = Join-Path $d '__acl_test__'
  New-Item -ItemType Directory $test -ErrorAction SilentlyContinue | Out-Null
  if (Test-Path $test) { "FAIL: create allowed in $d"; Remove-Item $test -Recurse -Force }
  else { "PASS: create denied in $d" }
}
```

Both must deny.

### 7. Guard task

```powershell
Get-ScheduledTask -TaskName WPSAI_Guard | Select TaskName, State
Get-Content 'C:\ProgramData\WPSAI_Guard\guard.log' -Tail 5
```

State `Ready`; log contains recent `checked` entries. The task triggers at logon and repeats every 10 minutes.

### 8. WPS still works locally

```powershell
Get-Process wps | Select Id, MainWindowTitle, Responding
```

The main window should show the document title and `Responding=True`. Open/save a local `.docx` to confirm. Cloud/login/online templates/AI are expected to fail in Full mode.

## Expected pass/fail table

| Layer | Pass | Fail symptom |
|---|---|---|
| Addons | Empty AI dirs | AI dirs reappear with files |
| Modules | No AI DLLs | `kwpsaigc`/`kcopilotentry` loaded |
| Registry | 0 AI keys/flags/tokens | Flags or tokens return |
| Configs | 0 AI entries | `setupplugin.plg` rewritten |
| Hosts | Block present | Hosts truncated/missing unrelated entries |
| Firewall | Rules present | No `WPSAI_Block_*` rules |
| ACL | Create denied | `__acl_test__` created |
| Guard | Task Ready + log | Task missing or never runs |

If a layer fails, re-run the corresponding script. If AI directories return **with files**, a source is still open: inspect `%TEMP%\wps`, old install roots, and `C:\WPSAI_Disabled` placement.
