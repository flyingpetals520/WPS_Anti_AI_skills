# Rollback

All changes are reversible. Run the restore script as administrator:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\98-restore.ps1
```

It removes the firewall rules, the guard task, restores the latest hosts backup, and removes the deny ACLs. It does **not** move quarantine folders back automatically; do that manually if you want the AI addons back.

## What the restore script does

1. Removes firewall rules named `WPSAI_Block_*`.
2. Unregisters scheduled task `WPSAI_Guard`.
3. Finds the latest hosts backup (`%TEMP%\wps-ai-blocker\hosts-*.bak` or `%TEMP%\hosts_before_wpsai_*.txt`) and copies it over the hosts file.
4. Removes the current user's deny ACEs from:
   - `<install-root>\office6\addons`
   - `%APPDATA%\kingsoft\wps\addons\pool\win-*`
5. Leaves `C:\WPSAI_Disabled` and `.wpsai_bak_*` files in place.

## Manual rollback

### Firewall

```powershell
Remove-NetFirewallRule -DisplayName "WPSAI_Block_*"
```

### Guard task

```powershell
Unregister-ScheduledTask -TaskName "WPSAI_Guard" -Confirm:$false
Remove-Item 'C:\ProgramData\WPSAI_Guard' -Recurse -Force
```

### Hosts

Restore the backup created before the first network lock:

```powershell
$bak = Get-ChildItem "$env:TEMP\wps-ai-blocker\hosts-*.bak","$env:TEMP\hosts_before_wpsai_*.txt" |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $bak.FullName "$env:WINDIR\System32\drivers\etc\hosts" -Force
```

If security software truncated the hosts file earlier, the backup contains the original unrelated VPN/agent lines.

### ACL

```powershell
$user = "$env:USERDOMAIN\$env:USERNAME"
icacls "<install-root>\office6\addons" /remove:d $user
icacls "$env:APPDATA\kingsoft\wps\addons\pool\win-i386" /remove:d $user
```

### Config files

Every edited file has a sibling `.wpsai_bak_<timestamp>`:

```text
office6\setupplugincfg\setupplugin.plg.wpsai_bak_*
office6\addons\kapplist\applist.xml.wpsai_bak_*
utility\crcmap.dat.wpsai_bak_*
utility\installfilelist.dat.wpsai_bak_*
%APPDATA%\...\kapplist_*\applist.xml.wpsai_bak_*
```

Copy the desired backup over the original and restore the read-only attribute.

### Registry

Backups:

```text
%TEMP%\setupPluginUpdate_before_wpsai_*.reg
%TEMP%\CloudSvrAppList_before_wpsai_*.txt
%TEMP%\plugins_before_wpsai_*.reg
```

Restore with `reg import` or by editing the values manually.

### Quarantine

The removed addons are under:

```text
C:\WPSAI_Disabled\install
C:\WPSAI_Disabled\pool
C:\WPSAI_Disabled\temp
C:\WPSAI_Disabled\reappeared*
```

Move the desired folders back to their original locations:

- install addons → `<install-root>\office6\addons\<name>`
- pool packages → `%APPDATA%\kingsoft\wps\addons\pool\win-i386\<name>`
- temp staging → `%TEMP%\wps\<name>` (usually not needed)

### Re-enable WPS network/updates

After removing the firewall rules, guard task, hosts block, and ACLs, restart WPS. WPS may auto-update and restore AI; re-run the blocker if needed.

## Notes

- Removing the ACL alone allows WPS to recreate AI placeholders but not the full packages if the network block remains.
- Removing the network block alone lets WPS download AI packages, but the ACL blocks installation and the guard removes them.
- For a temporary unblock (e.g., cloud documents), remove only the `WPSAI_Block_Net_*` rules and keep the AI/plugin domain blocks and ACL.
