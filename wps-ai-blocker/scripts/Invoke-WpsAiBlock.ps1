param(
  [ValidateSet('Audit','Apply','Full','Verify','Restore')]
  [string]$Mode = 'Audit',
  [string]$InstallRoot,
  [string]$QuarantineRoot = 'C:\WPSAI_Disabled',
  [switch]$NoFullOffline,
  [switch]$WhatIf
)

. "$PSScriptRoot\00-common.ps1"
Initialize-WpsAiLog -Name ('orchestrator-' + $Mode.ToLower())

if ($Mode -in @('Apply','Full','Restore') -and -not (Test-IsAdmin)) {
  $a = @('-Mode', $Mode, '-QuarantineRoot', $QuarantineRoot)
  if ($InstallRoot) { $a += @('-InstallRoot', $InstallRoot) }
  if ($NoFullOffline) { $a += '-NoFullOffline' }
  if ($WhatIf) { $a += '-WhatIf' }
  Ensure-Elevated -ScriptPath $PSCommandPath -Arguments $a
}

$script:FailCount = 0
function Invoke-Phase {
  param([string]$Script, [hashtable]$Parameters = @{})
  $path = Join-Path $PSScriptRoot $Script
  Write-WpsLog ("--- RUN {0}" -f $Script)
  & $path @Parameters
  $code = $LASTEXITCODE
  Write-WpsLog ("--- EXIT {0} code={1}" -f $Script, $code)
  if ($code -ne 0) { $script:FailCount++ }
  return $code
}

# Common hashtables avoid array-splatting ambiguity around switch parameters.
$base = @{}
if ($InstallRoot) { $base['InstallRoot'] = $InstallRoot }
if ($WhatIf) { $base['WhatIf'] = $true }

$reconParams = @{}
if ($InstallRoot) { $reconParams['InstallRoot'] = $InstallRoot }
$quarantineParams = @{ QuarantineRoot = $QuarantineRoot }
if ($InstallRoot) { $quarantineParams['InstallRoot'] = $InstallRoot }
if ($WhatIf) { $quarantineParams['WhatIf'] = $true }

$configParams = @{}
if ($InstallRoot) { $configParams['InstallRoot'] = $InstallRoot }
if ($WhatIf) { $configParams['WhatIf'] = $true }

$netParams = @{}
if ($InstallRoot) { $netParams['InstallRoot'] = $InstallRoot }
if (-not $NoFullOffline) { $netParams['FullOffline'] = $true }
if ($WhatIf) { $netParams['WhatIf'] = $true }

$aclParams = @{}
if ($InstallRoot) { $aclParams['InstallRoot'] = $InstallRoot }
if ($WhatIf) { $aclParams['WhatIf'] = $true }

$guardParams = @{}
if ($WhatIf) { $guardParams['WhatIf'] = $true }

$verifyParams = @{}
if ($InstallRoot) { $verifyParams['InstallRoot'] = $InstallRoot }

switch ($Mode) {
  'Audit' {
    Invoke-Phase '01-recon.ps1' $reconParams | Out-Null
  }
  'Apply' {
    Invoke-Phase '01-recon.ps1' $reconParams | Out-Null
    Invoke-Phase '02-quarantine-addons.ps1' $quarantineParams | Out-Null
    Invoke-Phase '03-clean-configs.ps1' $configParams | Out-Null
    Invoke-Phase '06-install-guard.ps1' $guardParams | Out-Null
    Invoke-Phase '99-verify.ps1' $verifyParams | Out-Null
  }
  'Full' {
    Invoke-Phase '01-recon.ps1' $reconParams | Out-Null
    Invoke-Phase '02-quarantine-addons.ps1' $quarantineParams | Out-Null
    Invoke-Phase '03-clean-configs.ps1' $configParams | Out-Null
    Invoke-Phase '04-network-lock.ps1' $netParams | Out-Null
    Invoke-Phase '05-acl-lock.ps1' $aclParams | Out-Null
    Invoke-Phase '06-install-guard.ps1' $guardParams | Out-Null
    Invoke-Phase '99-verify.ps1' $verifyParams | Out-Null
  }
  'Verify' {
    Invoke-Phase '99-verify.ps1' $verifyParams | Out-Null
  }
  'Restore' {
    Invoke-Phase '98-restore.ps1' $base | Out-Null
  }
}

Write-WpsLog ("=== ORCHESTRATOR COMPLETE mode={0} failed_phases={1} ===" -f $Mode, $script:FailCount)
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
