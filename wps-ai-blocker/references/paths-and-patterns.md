# Paths, Names, and Patterns

## Install roots

WPS is commonly installed in one of these locations; the actual version directory is the parent of `office6`:

- `C:\Program Files\WPS Office\<version>`
- `C:\Program Files (x86)\WPS Office\<version>`
- `C:\Program Files\Kingsoft\WPS Office\<version>`
- `C:\Program Files (x86)\Kingsoft\WPS Office\<version>`
- `C:\Users\<user>\AppData\Local\Kingsoft\WPS Office\<version>`
- Non-system drives, e.g. `F:\WPS\WPS Office\<version>`

Detect reliably from:

1. Running processes: `wps.exe`, `wpp.exe`, `et.exe`, `pdf.exe`, `wpsoffice.exe`, `ksolaunch.exe`.
2. Uninstall registry: `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall`, `HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`, `HKCU\...\Uninstall`, where `DisplayName` matches `WPS Office` or `Kingsoft`.
3. Common roots above, then enumerate version directories that contain `office6`.

An install root is valid only if `<root>\office6` exists.

## Addon and pool roots

```text
<install-root>\office6\addons
<install-root>\office6\setupplugincfg\setupplugin.plg
<install-root>\office6\addons\kapplist\applist.xml
<install-root>\utility\crcmap.dat
<install-root>\utility\installfilelist.dat
%APPDATA%\kingsoft\wps\addons\pool\win-i386
%APPDATA%\kingsoft\wps\addons\pool\win-amd64
%APPDATA%\kingsoft\wps\addons\pool\win-i386_wpsai_disabled   # legacy in-tree quarantine: do not use
%TEMP%\wps
%TEMP%\WPS                                                     # same directory as %TEMP%\wps
```

Also check older user-level installs:

```text
%LOCALAPPDATA%\Kingsoft\WPS Office\<version>\office6\addons
%LOCALAPPDATA%\Kingsoft\WPS Office\<version>\office6\setupplugincfg\setupplugin.plg
%LOCALAPPDATA%\Kingsoft\WPS Office\<version>\utility\crcmap.dat
%LOCALAPPDATA%\Kingsoft\WPS Office\<version>\utility\installfilelist.dat
```

## AI addon name regex

Use this as a case-insensitive **directory-name** regex:

```regex
(?i)^(kaiwpp|kcopilot|ketai|ketcopilot|kpdfai|kpdfcopilot|kpubaigcbox|ktaskpanelcopilot|kwebaireport|kwebwpscopilot|kwebaipdfinsight|kwebaihistory|kwebwpsdoccomposing|kwebwpsinstructioncenter|kwebwpsainewfilepanel|kwebwppaioutline|kwebwpsairesources|kwebaitoolbarskillbuilder|kwebwpsmathor|kwppai|kwppcopilot|kwpsai|kwpscopilot|karticlewebcloudsummary|kwpsthesisassistant|kwpsailingxi)
```

For config/line content, use a broader line regex:

```regex
(?i)(kaiwpp|kcopilot|ketai|ketcopilot|kpdfai|kpdfcopilot|kpubaigcbox|ktaskpanelcopilot|kwebaireport|kwebwpscopilot|kwebaipdfinsight|kwebaihistory|kwebwpsdoccomposing|kwebwpsinstructioncenter|kwebwpsainewfilepanel|kwebwppaioutline|kwebwpsairesources|kwebaitoolbarskillbuilder|kwebwpsmathor|kwppai|kwppcopilot|kwpsai|kwpscopilot|karticlewebcloudsummary|kwpsthesisassistant|kwpsailingxi)
```

Versioned pool folders end with `_<major>.<minor>.<patch>.<build>`; the regex matches the prefix.

## Registry keys

```text
HKCU\Software\Kingsoft\Office\6.0\Common\ResourceManager\setupPluginUpdate
HKCU\Software\Kingsoft\Office\6.0\plugins\kappmgr  (CloudSvrAppList)
HKCU\Software\Kingsoft\Office\6.0\plugins\<ai-plugin-name>
HKCU\Software\Kingsoft\Office\6.0\plugins\kstartpage\officenav_new_v1\seqEntry\CommonEntrys
  values: wpsaiassistant, wpsaippt
HKCU\Software\Kingsoft\Office\6.0\Common\updateinfo
```

- `setupPluginUpdate` values are strings `1`; remove values whose names match the AI regex.
- `CloudSvrAppList` is a long comma-separated list with a `version:...,pid:...|<hash>` prefix; split on `,`, filter AI tokens, rejoin.
- AI plugin keys are per-plugin state; delete the whole key.
- `updateinfo\UpdateMode` should be `manual` or the update task disabled; do not rely on it alone.

## Scheduled tasks

```text
WpsUpdateTask_<user>
WpsUpdateLogonTask_<user>
WpsWakeWnsLogonTask
```

Delete with `schtasks /Delete /TN "<name>" /F` or `Unregister-ScheduledTask -TaskName "<name>" -Confirm:$false`. They may be recreated by WPS; the guard task re-disables them.

## Domains for hosts blocking

```text
abp.wps.cn
365.kdocs.cn
wpscdn.cn
down.wps.cn
dl.wps.cn
update.wps.cn
wpsupdate.wps.cn
update.wpscdn.cn
ks3-cn-beijing.ksyun.com
dldir1.qq.com                 # WPS update CDN; may affect other Tencent downloads
pc-update-1.wpscdn.cn ... pc-update-10.wpscdn.cn
```

Hosts does **not** support wildcards; list each hostname.

## Firewall

Block **outbound** for update executables:

```text
<install-root>\wtoolex\wpsupdate.exe
<install-root>\wtoolex\updateself.exe
<install-root>\wtoolex\updatepolicy.exe
<WPS-launcher>\ksolaunch.exe
%APPDATA%\kingsoft\office6\update\down\wpsupdate.exe
%APPDATA%\kingsoft\office6\update\down\updateself.exe
```

For full offline, block every `.exe` under `<install-root>\office6`, `<install-root>\wtoolex`, `<install-root>` (top-level only), and old user-level install `office6` folders.

Rule names: `WPSAI_Block_Update_<n>` and `WPSAI_Block_Net_<n>`.

## Quarantine layout

```text
C:\WPSAI_Disabled\
  install\        # install addon folders moved out of office6\addons
  pool\           # pool packages moved out of win-*\.
  temp\           # %TEMP%\wps AI staging folders
  reappeared*\     # batches recovered by the guard
  logs\
```

Keep quarantine on the same volume as the source for fast moves when possible.

## Guard task

```text
Task name: WPSAI_Guard
Script:    C:\ProgramData\WPSAI_Guard\wpsai_guard.ps1
Log:       C:\ProgramData\WPSAI_Guard\guard.log
Trigger:   At logon + every 10 minutes
Principal: current user, RunLevel Highest, Interactive
```
