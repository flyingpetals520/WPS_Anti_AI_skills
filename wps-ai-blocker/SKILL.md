---
name: wps-ai-blocker
description: Use when WPS Office AI features (WPS AI, Copilot, Lingxi/灵犀) must be removed or prevented from returning after restart or update on Windows, or when WPS re-downloads AI plugins into its addon pool despite deletion, or when WPS update tasks or cloud pushes reinstall AI components.
---

# WPS AI Blocker

## Overview

WPS Office installs AI features as **addons** (`kwpsaigc`, `kcopilotentry`, `kwpscopilot`, `klingxidockpanel`, `kwpslingxi`, and related ET/PPT/PDF Copilot packages). They are restored by several independent mechanisms:

- `office6\setupplugincfg\setupplugin.plg` plugin registrations
- the addon pool (`%APPDATA%\kingsoft\wps\addons\pool\win-*`)
- `%TEMP%\wps` update/staging packages
- install manifests (`utility\crcmap.dat`, `utility\installfilelist.dat`)
- `HKCU\...\ResourceManager\setupPluginUpdate` flags
- `HKCU\...\plugins\kappmgr\CloudSvrAppList` app tokens
- WPS update scheduled tasks
- `applist.xml` entries

Deleting one folder is never enough. This skill removes every layer, blocks the network endpoints, denies directory creation in the addon roots, and installs a recurring guard task.

## When to Use

- The WPS AI / WPS Copilot / 灵犀 (Lingxi) tab, toolbar, or dock panel must disappear.
- WPS recreates AI addon folders after restart, update, or login.
- WPS updates or cloud pushes reinstall AI plugins.
- You need a repeatable, reversible procedure for another Windows machine.

**Do not use** to uninstall WPS itself. `-Mode Full` keeps local editing but makes WPS fully offline.

## Safety and Side Effects

- `-Mode Full` blocks **all outbound traffic** for WPS executables: cloud documents, login, online templates, AI, and updates stop. Local open/edit/save/print still work.
- The ACL lock denies **all** addon installs and updates, not only AI.
- Close WPS and save documents before applying. Loaded DLLs cannot be moved or deleted.
- Every change is reversible: `.wpsai_bak_*` files, `C:\WPSAI_Disabled`, hosts backup, registry `.reg` backup, and the restore script.
- Run only on a machine you own or are authorized to administer.

## Quick Start

```powershell
# 1. Close all WPS windows and save your work.
# 2. Read-only inventory
powershell -ExecutionPolicy Bypass -File scripts\01-recon.ps1

# 3. Apply the full block (requests UAC)
powershell -ExecutionPolicy Bypass -File scripts\Invoke-WpsAiBlock.ps1 -Mode Full

# 4. Verify
powershell -ExecutionPolicy Bypass -File scripts\99-verify.ps1

# 5. Reopen WPS: no AI tab; local docx should open normally.
```

## Phases

| Script | Purpose | Admin |
|---|---|---|
| `scripts\00-common.ps1` | Detection, logging, shared helpers | No |
| `scripts\01-recon.ps1` | Read-only inventory of install roots, addons, configs, registry, network, tasks | No |
| `scripts\02-quarantine-addons.ps1` | Move AI addons, pool packages, and `%TEMP%\wps` staging outside the WPS tree | No* |
| `scripts\03-clean-configs.ps1` | Remove AI entries from `setupplugin.plg`, manifests, `applist.xml`, registry | No |
| `scripts\04-network-lock.ps1` | Hosts block + outbound firewall rules | Yes |
| `scripts\05-acl-lock.ps1` | Deny create/write on addon roots (`AD,WD`) | Yes for install root |
| `scripts\06-install-guard.ps1` | Install `WPSAI_Guard` task: logon + every 10 minutes | Yes |
| `scripts\99-verify.ps1` | PASS/FAIL verification | No |
| `scripts\98-restore.ps1` | Remove firewall rules, guard task, hosts block, ACLs | Yes |
| `scripts\Invoke-WpsAiBlock.ps1` | Orchestrator: `Audit`, `Apply`, `Full`, `Verify`, `Restore` | Depends |

\* Moving files inside `F:\WPS\...\addons` may require write permission; the script reports failures and can be re-run elevated.

## Core Rules

1. **Quarantine outside the WPS tree.** Never leave `*_disabled` folders under `addons` or `pool`; WPS scans them and copies packages back. Default quarantine is `C:\WPSAI_Disabled`.
2. **Clean `%TEMP%\wps`.** It stores `Update.cfg`, `.bin2`, and diff files used to recreate AI packages on restart.
3. **Edit `crcmap.dat` as UTF-16LE and `installfilelist.dat` byte-wise.** Decoding them as UTF-8 corrupts paths.
4. **Use 32-bit PowerShell to enumerate WPS modules.** 64-bit PowerShell cannot see 32-bit WPS DLLs; run `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`.
5. **Security software may block hosts writes.** Back up hosts first, verify the file size after writing, preserve unrelated VPN/agent entries, and treat firewall rules as the primary network block.
6. **`setupPluginUpdate` flags and `CloudSvrAppList` tokens are re-added by WPS.** The guard task removes them every 10 minutes.
7. **ACL deny `(AD,WD)` on the pool and addons folders stops even empty placeholder directories.** Verify with a create test.
8. **Update tasks may hang on `Unregister-ScheduledTask`.** Use `schtasks /Delete /F` or leave them Disabled; the guard re-disables them.
9. **Do not delete `C:\Program Files (x86)\Kingsoft`.** It is the WPS Cloud Service, not Lingxi.

## Verification

A clean machine shows:

- No AI directories under install `office6\addons`, pool `win-*`, or `%TEMP%\wps`.
- No `kwpsai*` / `kcopilot*` / `klingxidockpanel` modules loaded (32-bit check).
- No AI plugin keys, `setupPluginUpdate` flags, or `CloudSvrAppList` tokens.
- Hosts block present; firewall `WPSAI_Block_*` rules present; WPS update tasks absent or disabled.
- Directory creation denied in `addons` and `pool\win-*`.
- `WPSAI_Guard` task Ready and `C:\ProgramData\WPSAI_Guard\guard.log` receives `checked` entries.

See `references/verification.md` for exact commands.

## Validation

Tested on Windows 11 with WPS 12.1.x on a non-system drive plus a leftover older user-level install:

- Baseline `99-verify.ps1`: `pass=11 fail=4` (old-version AI dirs, config refs, update task Ready, ACL gaps).
- After `Invoke-WpsAiBlock.ps1 -Mode Full`: all phases exit 0, `45` firewall programs blocked in FullOffline mode, `99-verify.ps1` `pass=15 fail=0`.
- After reopening WPS: no AI tab and local `.docx` editing works.

See `references/validation.md` for the full RED/GREEN record and the two bugs found during validation (non-system-drive detection and `-FullOffline` parameter splatting).

## Rollback

```powershell
powershell -ExecutionPolicy Bypass -File scripts\98-restore.ps1
```

Then move quarantine folders back manually if desired. See `references/rollback.md`.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Deleting only `kwpslingxi`/`klingxidockpanel` | Also remove `kwpsaigc`, `kcopilotentry`, `kwpscopilot`, ET/PPT/PDF Copilot, applist entries, manifests, temp staging |
| Leaving `*_disabled` inside `addons`/`pool` | Move quarantine outside the WPS tree |
| Decoding `crcmap.dat` as UTF-8 | Use UTF-16LE |
| Checking modules from 64-bit PowerShell | Use `SysWOW64\WindowsPowerShell` |
| Writing hosts without a backup | Always back up and verify; security software may truncate |
| Assuming install is under `C:\Program Files` | Detect from running `wps.exe`, uninstall entries, and common roots |
| Blocking only update exes | AI packages can be fetched by `wps.exe`; use `-FullOffline` or block the AI/plugin domains |
| Applying ACL before moving addons | Move first, then deny create/write |

## References

- `references/paths-and-patterns.md` — install/pool/temp paths, AI name regex, domains, registry keys, task names
- `references/pitfalls.md` — observed failure modes and root causes
- `references/verification.md` — PASS/FAIL checks
- `references/rollback.md` — restore procedure and backup locations
