# Pitfalls and Root Causes

These are the traps observed while dismantling WPS AI on a real Windows 11 machine. Read this before applying the skill.

## 1. WPS is not always under `C:\Program Files`

The observed install was on a non-system drive (e.g. `<install-root>`), while `C:\Program Files (x86)\Kingsoft` contained only the WPS Cloud Service (`wpscloudsvr.exe`). Never assume Program Files; detect from running `wps.exe`, uninstall entries, and common roots.

## 2. `setupplugin.plg` alone does nothing

Removing AI `<plugin>` entries from `setupplugin.plg` did not stop `kwpsaigc` / `kcopilotentry` / `kwpscopilot` from loading. WPS also scans `<install>\office6\addons` and the pool `win-*` directories directly. You must move the addon folders.

## 3. In-tree `*_disabled` folders are scanned

Moving AI folders to `<install>\office6\addons_wpsai_disabled` or `%APPDATA%\...\pool\win-i386_wpsai_disabled` caused WPS to copy the packages back. Quarantine must be **outside** the WPS tree, e.g. `C:\WPSAI_Disabled`.

## 4. `%TEMP%\wps` is a staging source

WPS stores update packages there as `Update.cfg`, `.bin2`, and `diff_resource_file.json`. After restart, it copied `kcopilotentry`, `kpdfaibookmark`, `kwppcopilotentry`, `kwpsaitypeset` back into the pool. Clean `%TEMP%\wps` (and `%TEMP%\WPS`, same directory) as part of quarantine and guard.

## 5. Install manifests restore missing files

`<install>\utility\crcmap.dat` and `installfilelist.dat` list every installed file, including AI addons. WPS self-repair used them to restore files. Remove AI lines from both, for every install root (including old user-level versions).

## 6. Encoding traps

- `crcmap.dat` is **UTF-16LE**, line-separated by `\r\0\n\0`, records `path,hash`.
- `installfilelist.dat` is **not pure UTF-8**; it contains legacy bytes. Operate on bytes or decode as Latin-1 for path matching.
- `setupplugin.plg` and `applist.xml` are UTF-8, `\r\n` and `\n` respectively; do not change their line endings.
- Clear the read-only attribute before editing and restore it afterward.

## 7. Registry flags are re-added at startup

`HKCU\Software\Kingsoft\Office\6.0\Common\ResourceManager\setupPluginUpdate` values such as `kcopilotentry=1`, `kwpsaigc=1`, `kwpscopilot=1` reappear after WPS starts. Removing them once is not enough; the guard task must remove them repeatedly.

`CloudSvrAppList` tokens (`kwpsaigc`, `kwpsaidoc2ppt`, `kpdfcopilot`, `ai_space`, `aivideo`, `AiSmartOrganize`) are also re-added.

## 8. 32-bit module enumeration

WPS is 32-bit. A 64-bit PowerShell `Get-Process wps | % Modules` silently misses `kwpslingxi.dll` and `klingxidockpanel.dll`. Use:

```powershell
& "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "..."
```

## 9. Hosts files can be blocked or truncated

A HIPS product blocked `Set-Content` on `C:\Windows\System32\drivers\etc\hosts`; the first attempt left the file truncated to 37 bytes. Always:

- back up hosts before writing;
- write to a temp file, then `Copy-Item` over the hosts file;
- preserve unrelated VPN/agent entries;
- verify the file size/content after writing;
- treat firewall rules as the primary network block if hosts writes are blocked.

VPN/security agents may rewrite hosts; re-check after a reboot.

## 10. UAC and elevated scripts

`Start-Process -Verb RunAs` works but the UAC prompt may appear behind windows or time out. For reliable elevation:

- write a `.ps1` to `C:\Temp`;
- launch it with `Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',...`;
- have the elevated script write a result file that the non-elevated session reads.

## 11. Scheduled task deletion can hang

`Unregister-ScheduledTask` hung once (likely a security-software prompt). `schtasks /Delete /TN "<name>" /F` is a useful alternative. A disabled task is sufficient; the guard re-disables it.

## 12. ACL deny blocks placeholders

WPS created **empty** AI pool directories on every start after the network block. A deny ACE for the current user on the pool and addons folders:

```powershell
icacls "<dir>" /deny "<DOMAIN\user>:(AD,WD)"
```

stopped creation. Apply **after** moving existing AI folders. Test:

```powershell
$test = Join-Path $dir '__acl_test__'
New-Item -ItemType Directory $test -ErrorAction SilentlyContinue
Test-Path $test   # must be False
```

The ACL also blocks non-AI addon installs/updates; this is intentional for a locked machine.

## 13. `wps.exe` outbound block has side effects

Blocking all WPS executables stops cloud documents, login, online templates, AI, and updates. Local editing still works. Make this explicit to the user; use `-FullOffline` deliberately.

## 14. Do not delete the WPS Cloud Service

`C:\Program Files (x86)\Kingsoft\office6\wpscloudsvr.exe` is not Lingxi. Deleting the `Kingsoft` folder may break WPS cloud features and uninstall/repair.

## 15. Old WPS versions are additional sources

`%LOCALAPPDATA%\Kingsoft\WPS Office\<version>` can contain `applist.rcc` with `kwpsailingxi` and `https://365.kdocs.cn/3rd/lingxi/`, plus older manifests. Treat every detected install root, not just the running version.

## 16. Empty directories are a symptom, not the disease

If AI pool dirs reappear but contain **zero files**, the network is already blocked; WPS is only creating placeholders. The ACL lock is the final fix. If they contain files, a local cache or network path is still open; re-run reconnaissance.

## 17. Guard task triggers

At logon does not fire when only WPS is restarted. Use a repetition interval (10 minutes) in addition to `AtLogOn`. Run the task as the current user with `RunLevel Highest`, hidden window, and log to `C:\ProgramData\WPSAI_Guard\guard.log`.

## 18. Do not fight WPS while documents are open

Loaded DLLs cannot be moved. Ask the user to save and close all WPS windows before applying the full block. The ACL and guard can be applied while WPS is running, but the visual result (tab disappearing) requires a restart.
