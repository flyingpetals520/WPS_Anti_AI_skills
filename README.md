# WPS Anti-AI Skills

A Windows PowerShell skill for **removing WPS Office AI / WPS Copilot / 灵犀 (Lingxi) components and preventing them from being reinstalled by updates, cloud pushes, or WPS self-repair**.

> **中文简介**：本仓库提供一个 Windows PowerShell 技能包，用于彻底移除 WPS Office 的 WPS AI / Copilot / 灵犀组件，并通过配置清理、网络封锁、目录 ACL 锁定和定时守卫任务，防止这些组件在 WPS 重启、更新或云端下发后重新出现。

> **Legal / intended use:** Read [DISCLAIMER.md](DISCLAIMER.md) before running. Use only on machines you own or are authorized to administer. These scripts do not bypass licensing, activation, or paid features, and come with no warranty.

WPS AI is not a single file. It is a collection of addons (`kwpsaigc`, `kcopilotentry`, `kwpscopilot`, `klingxidockpanel`, `kwpslingxi`, ET/PPT/PDF Copilot packages, and related web apps) restored by several independent mechanisms:

- plugin registrations in `office6\setupplugincfg\setupplugin.plg`
- the addon pool under `%APPDATA%\kingsoft\wps\addons\pool\win-*`
- update/staging packages in `%TEMP%\wps`
- install manifests (`utility\crcmap.dat`, `utility\installfilelist.dat`)
- `setupPluginUpdate` registry flags and `CloudSvrAppList` tokens
- `applist.xml` entries
- WPS update scheduled tasks and cloud pushes

Deleting one folder is never enough. This skill handles every layer and leaves a recurring guard behind.

## What It Does

| Phase | Script | Purpose | Admin |
|---|---|---|---|
| Recon | `scripts/01-recon.ps1` | Read-only inventory of install roots, addons, pool, temp, configs, registry, firewall, tasks | No |
| Quarantine | `scripts/02-quarantine-addons.ps1` | Move AI addons, pool packages, and `%TEMP%\wps` staging outside the WPS tree | No* |
| Clean configs | `scripts/03-clean-configs.ps1` | Remove AI entries from `setupplugin.plg`, manifests, `applist.xml`, and registry | No |
| Network lock | `scripts/04-network-lock.ps1` | Hosts block for WPS update/plugin/AI domains plus outbound firewall rules | Yes |
| ACL lock | `scripts/05-acl-lock.ps1` | Deny create/write (`AD,WD`) on install `addons` and pool `win-*` roots | Yes for install root |
| Guard | `scripts/06-install-guard.ps1` | Install `WPSAI_Guard`: runs at logon and every 10 minutes | Yes |
| Verify | `scripts/99-verify.ps1` | PASS/FAIL checks for every layer | No |
| Restore | `scripts/98-restore.ps1` | Remove firewall rules, guard task, hosts block, and ACLs | Yes |

\* Moving files inside `F:\WPS\...\addons` may require write permission; run elevated if a move fails.

The orchestrator `scripts/Invoke-WpsAiBlock.ps1` combines the phases.

## Repository Layout

```text
WPS_Anti_AI_skills/
├─ README.md
└─ wps-ai-blocker/
   ├─ SKILL.md
   ├─ references/
   │  ├─ paths-and-patterns.md
   │  ├─ pitfalls.md
   │  ├─ verification.md
   │  ├─ validation.md
   │  └─ rollback.md
   └─ scripts/
      ├─ 00-common.ps1
      ├─ 01-recon.ps1
      ├─ 02-quarantine-addons.ps1
      ├─ 03-clean-configs.ps1
      ├─ 04-network-lock.ps1
      ├─ 05-acl-lock.ps1
      ├─ 06-install-guard.ps1
      ├─ 98-restore.ps1
      ├─ 99-verify.ps1
      ├─ guard-template.ps1
      └─ Invoke-WpsAiBlock.ps1
```

## Requirements

- Windows 10/11.
- Windows PowerShell 5.1 (the scripts use `SysWOW64` PowerShell for 32-bit WPS module checks).
- WPS Office 12.x; validated on a running install and a leftover older user-level install.
- Administrator rights for network, ACL, and guard phases.
- **Close all WPS windows and save your documents before applying.**
- Run only on a machine you own or are authorized to administer.

## Quick Start

```powershell
git clone https://github.com/flyingpetals520/WPS_Anti_AI_skills.git
cd WPS_Anti_AI_skills\wps-ai-blocker

# 1. Read-only inventory
powershell -ExecutionPolicy Bypass -File .\scripts\01-recon.ps1

# 2. Full block (requests UAC)
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpsAiBlock.ps1 -Mode Full

# 3. Verify
powershell -ExecutionPolicy Bypass -File .\scripts\99-verify.ps1

# 4. Reopen WPS: the AI tab should be gone; local .docx editing should still work.
```

### Modes

```powershell
# Inventory only, makes no changes
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpsAiBlock.ps1 -Mode Audit

# Quarantine + config cleanup + guard, without network/ACL locks
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpsAiBlock.ps1 -Mode Apply

# Everything: quarantine + cleanup + network lock + ACL lock + guard
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpsAiBlock.ps1 -Mode Full

# Only run the PASS/FAIL verifier
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpsAiBlock.ps1 -Mode Verify

# Revert all changes
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpsAiBlock.ps1 -Mode Restore
```

Useful switches:

- `-NoFullOffline` — keep some WPS online features by blocking only update/plugin/AI endpoints and update executables instead of all WPS outbound traffic.
- `-InstallRoot <path>` — override WPS install-root detection.
- `-QuarantineRoot <path>` — change the quarantine directory (default `C:\WPSAI_Disabled`).
- `-WhatIf` — report intended actions without changing files.

## How It Works

1. **Detect every WPS root** — running processes, uninstall registry entries, `InstallRoot`, scheduled task actions, and common paths. Non-system-drive installs are supported.
2. **Quarantine outside the WPS tree** — AI addons, pool packages, and `%TEMP%\wps` staging are moved to `C:\WPSAI_Disabled`. WPS scans its own `addons`/`pool` trees; leaving `*_disabled` folders inside them causes resurrection.
3. **Clean configs** — removes AI entries from `setupplugin.plg`, `crcmap.dat`, `installfilelist.dat`, `applist.xml`, `setupPluginUpdate`, `CloudSvrAppList`, and per-plugin registry keys.
4. **Network lock** — writes a hosts block for 20 update/plugin/AI domains and creates `WPSAI_Block_*` outbound firewall rules. `Full` mode blocks all detected WPS executables (45 programs in validation); `-NoFullOffline` limits the block to update/plugin/AI channels.
5. **ACL lock** — applies `DENY(AD,WD)` on the install `addons` and pool `win-*` roots, so WPS cannot create even empty AI placeholder directories.
6. **Recurring guard** — `WPSAI_Guard` runs at logon and every 10 minutes, moving any new AI addon, cleaning registry/config entries, re-disabling update tasks, and ensuring the hosts block exists.

## Validation

Validated on Windows 11 with WPS 12.1.x, a leftover older user-level install, and a HIPS product:

- Before: `99-verify.ps1` → `pass=11 fail=4`
- After `Invoke-WpsAiBlock.ps1 -Mode Full`: all phases exit `0`, 45 WPS programs blocked, `99-verify.ps1` → `pass=15 fail=0`
- After reopening WPS: no AI tab, no AI DLLs loaded, local `.docx` editing works

See `wps-ai-blocker/references/validation.md` for the full RED/GREEN record.

## Safety and Side Effects

- **`Full` mode makes WPS fully offline**: cloud documents, login, online templates, AI, and updates stop. Local open/edit/save/print still work.
- The ACL lock denies **all** addon installs and updates, not only AI.
- Every change is reversible: `.wpsai_bak_*` files, `C:\WPSAI_Disabled`, hosts backup, registry `.reg` backup, and `98-restore.ps1`.
- Security software (HIPS/firewall tools) may block hosts writes or firewall changes. The scripts back up hosts and verify file size; firewall rules are the primary network block.
- Do not delete `C:\Program Files (x86)\Kingsoft` — that is the WPS Cloud Service, not Lingxi.

## Rollback

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\98-restore.ps1
```

Then move quarantine folders back from `C:\WPSAI_Disabled` if desired. See `wps-ai-blocker/references/rollback.md`.

## References

- `wps-ai-blocker/SKILL.md` — full skill instructions, phases, rules, and common mistakes
- `wps-ai-blocker/references/paths-and-patterns.md` — paths, AI name regex, registry keys, task names
- `wps-ai-blocker/references/pitfalls.md` — observed failure modes and root causes
- `wps-ai-blocker/references/verification.md` — exact PASS/FAIL checks
- `wps-ai-blocker/references/rollback.md` — restore procedure and backup locations
- `wps-ai-blocker/references/validation.md` — real-machine RED/GREEN record

## Disclaimer

See [DISCLAIMER.md](DISCLAIMER.md) for the full legal and intended-use notice.

This project is not affiliated with Kingsoft or WPS Office. It modifies local configuration, firewall rules, file ACLs, and scheduled tasks. Use it at your own risk, test on a non-critical machine first, and keep the generated backups until you have confirmed the result. "WPS" and related marks belong to their respective owners.
