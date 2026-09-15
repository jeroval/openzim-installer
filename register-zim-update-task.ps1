#requires -Version 5.1

<#
.SYNOPSIS
Enregistre une mise a jour hebdomadaire de la bibliotheque ZIM.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string] $ConfigPath,

    [Parameter()]
    [string] $TaskName = 'Local AI - Update Kiwix ZIM Library',

    [Parameter()]
    [string] $LibraryRoot = 'C:\AI\Knowledge\ZIM',

    [Parameter()]
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string] $DayOfWeek = 'Sunday',

    [Parameter()]
    [datetime] $At = '03:00',

    [Parameter()]
    [switch] $IncludeOptional,

    [Parameter()]
    [switch] $RemovePrevious
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'openzim.config.json'
}

$managerPath = Join-Path $PSScriptRoot 'manage-zim-library.ps1'
if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) {
    throw "Gestionnaire introuvable : $managerPath"
}

$arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$managerPath`" -Action Update -ConfigPath `"$ConfigPath`" -LibraryRoot `"$LibraryRoot`" -Confirm:`$false"
if ($IncludeOptional) {
    $arguments += ' -IncludeOptional'
}
if ($RemovePrevious) {
    $arguments += ' -RemovePrevious'
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $DayOfWeek -At $At
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

if ($PSCmdlet.ShouldProcess($TaskName, 'Enregistrer la tache planifiee')) {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description 'Verifie le catalogue Kiwix et telecharge les nouvelles archives ZIM.' `
        -Force | Out-Null

    Write-Host "Tache enregistree : $TaskName" -ForegroundColor Green
}
