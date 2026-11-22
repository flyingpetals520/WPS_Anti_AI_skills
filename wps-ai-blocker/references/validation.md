# Validation Record

This skill was validated on a real Windows 11 machine with:

- Running install: `<install-root>`
- Leftover user install: `<user-install-root>`
- Leftover version directory: `<old-install-root>`
- Pool: `%APPDATA%\kingsoft\wps\addons\pool\win-i386`
- Security software: a HIPS product
- WPS 32-bit; `SysWOW64\WindowsPowerShell` required for module checks

## RED: baseline failures

`99-verify.ps1` before applying the full block to every root:

```text
PASS  AI dirs in pool count=0
PASS  AI dirs in %TEMP%\wps count=0
PASS  No AI DLLs loaded
PASS  setupPluginUpdate AI flags count=0
PASS  CloudSvrAppList AI tokens count=0
PASS  AI plugin registry keys count=0
PASS  Hosts WPS block
PASS  Hosts unrelated entries preserved
PASS  Firewall WPSAI_Block_* rules count=50
PASS  Guard task present Ready
PASS  Guard log exists
FAIL  AI dirs in install addons count=38
FAIL  AI refs in config/manifests count=18
FAIL  WPS update tasks absent or disabled count=1
FAIL  Addon/pool create denied
      <user-install-root>\office6\addons:False
      <old-install-root>\office6\addons:False
      <install-root>\office6\addons:True
      %APPDATA%\...\win-i386:True

SUMMARY pass=11 fail=4
```

Root causes found during validation:

1. Initial install-root detection missed the non-system-drive install (`F:\WPS\...`) because the uninstall `InstallLocation` was empty. Fixed by reading:
   - `HKCU/HKLM\Software\Kingsoft\Office\6.0\Common\InstallRoot`
   - uninstall `DisplayIcon`
   - uninstall `UninstallString` (`...\utility\uninst.exe`)
   - scheduled update task action (`ksolaunch.exe`)
2. The leftover older user install still had 38 AI addons and 18 config refs. Fixed by processing **all** detected roots, not just the running one.
3. The orchestrator passed `-FullOffline` through array splatting in a way that bound it to `-InstallRoot`; only the two update-cache exes were blocked. Fixed by using hashtable splatting for switch parameters.
4. The update task was recreated by WPS and was `Ready` between guard runs. The guard disables it every 10 minutes; verify treats a transient Ready task as a failure until the guard runs. Run the guard or wait.

## GREEN: after the fix

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Invoke-WpsAiBlock.ps1 -Mode Full
```

Orchestrator log:

```text
EXIT 01-recon.ps1 code=0
EXIT 02-quarantine-addons.ps1 code=0
EXIT 03-clean-configs.ps1 code=0
EXIT 04-network-lock.ps1 code=0
EXIT 05-acl-lock.ps1 code=0
EXIT 06-install-guard.ps1 code=0
EXIT 99-verify.ps1 code=0
ORCHESTRATOR COMPLETE mode=Full failed_phases=0
```

`04` log:

```text
Hosts block written: 20 domains, size 2390
SUMMARY firewall programs blocked: 45; full offline: True
```

`99-verify.ps1`:

```text
PASS  AI dirs in install addons count=0
PASS  AI dirs in pool count=0
PASS  AI dirs in %TEMP%\wps count=0
PASS  No AI DLLs loaded
PASS  setupPluginUpdate AI flags count=0
PASS  CloudSvrAppList AI tokens count=0
PASS  AI plugin registry keys count=0
PASS  AI refs in config/manifests count=0
PASS  Hosts WPS block
PASS  Hosts unrelated entries preserved
PASS  Firewall WPSAI_Block_* rules count=45
PASS  WPS update tasks absent or disabled count=1
PASS  Addon/pool create denied
      <user-install-root>\office6\addons:True
      <old-install-root>\office6\addons:True
      <install-root>\office6\addons:True
      %APPDATA%\...\win-i386:True
PASS  Guard task present Ready
PASS  Guard log exists

SUMMARY pass=15 fail=0
```

WPS was not running during the final verification; after reopening, the AI tab remained gone and local `.docx` editing worked. Full offline mode means cloud/login/templates/AI/updates are unavailable, by design.

## Reproducing the test

1. Start with a machine that has AI addons present (or restore a quarantine folder).
2. Run `99-verify.ps1`; expect failures.
3. Run `Invoke-WpsAiBlock.ps1 -Mode Full` elevated.
4. Run `99-verify.ps1`; expect `pass` with `fail=0`.
5. Open WPS, confirm no AI tab; open/save a local docx.
