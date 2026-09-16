#requires -Version 5.1

<#
.SYNOPSIS
Gere la mise a jour hebdomadaire de la bibliotheque ZIM.

.DESCRIPTION
Permet de creer, inspecter, lancer immediatement ou supprimer la tache Windows
utilisee pour mettre a jour les archives ZIM. L'action `Status` est passive.
L'action `Run` execute la vraie commande de mise a jour et peut donc telecharger
de nouvelles archives si le catalogue Kiwix en contient.

.EXAMPLE
.\scripts\Invoke-ZimScheduledTask.ps1 -Action Status

.EXAMPLE
.\scripts\Invoke-ZimScheduledTask.ps1 -Action Run

.EXAMPLE
.\scripts\Invoke-ZimScheduledTask.ps1 -Action Remove
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateSet('Create', 'Status', 'Run', 'Remove')]
    [string] $Action = 'Create',

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
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repositoryRoot 'config\OpenZim.Settings.json'
}

$managerPath = Join-Path $PSScriptRoot 'Invoke-ZimLibrary.ps1'
if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) {
    throw "Gestionnaire introuvable : $managerPath"
}

# region Lecture et affichage de la tache Windows
function Get-OpenZimScheduledTask {
    # Get-ScheduledTask accepte des motifs. Le filtre exact evite de manipuler
    # accidentellement une autre tache dont le nom serait proche.
    $script:TaskReadError = $null
    try {
        return Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop |
            Where-Object TaskName -EQ $TaskName |
            Select-Object -First 1
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'CmdletizationQuery_NotFound*' -or
            $_.Exception.Message -match 'No MSFT_ScheduledTask|introuvable|not found') {
            return $null
        }
        $script:TaskReadError = $_.Exception.Message
        return $null
    }
}

function Show-OpenZimScheduledTask {
    param([Parameter()] $Task)

    Write-Host "`nETAT DE LA MISE A JOUR PLANIFIEE" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($script:TaskReadError)) {
        Write-Host '  Presence         : non verifiable (acces refuse)' -ForegroundColor Yellow
        Write-Host "  Erreur Windows   : $script:TaskReadError"
        Write-Host '  Conseil          : relancez l assistant normalement ; si le probleme persiste, essayez une fois en administrateur.'
        return
    }
    if ($null -eq $Task) {
        Write-Host '  Presence         : absente' -ForegroundColor Yellow
        Write-Host "  Nom attendu      : $TaskName"
        Write-Host '  Conseil          : choisissez Creer dans le menu de planification.'
        return
    }

    $taskInfo = Get-ScheduledTaskInfo -InputObject $Task
    $lastRun = if ($taskInfo.LastRunTime.Year -le 2000) { 'jamais executee' } else { $taskInfo.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss') }
    $nextRun = if ($taskInfo.NextRunTime.Year -le 2000) { 'non planifiee' } else { $taskInfo.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss') }
    $lastResult = if ($taskInfo.LastTaskResult -eq 0) {
        '0 (succes)'
    }
    else {
        '{0} (0x{1:X8})' -f $taskInfo.LastTaskResult, $taskInfo.LastTaskResult
    }

    Write-Host '  Presence         : installee' -ForegroundColor Green
    Write-Host "  Nom              : $($Task.TaskName)"
    Write-Host "  Etat Windows     : $($Task.State)"
    Write-Host "  Prochaine fois   : $nextRun"
    Write-Host "  Dernier lancement: $lastRun"
    Write-Host "  Dernier resultat : $lastResult"
    if ($Task.Actions.Count -gt 0) {
        Write-Host "  Programme        : $($Task.Actions[0].Execute)"
        Write-Host "  Arguments        : $($Task.Actions[0].Arguments)"
    }
    Write-Host '  Note             : un resultat autre que 0 doit etre examine apres la fin de la tache.'
}
# endregion Lecture et affichage de la tache Windows

# region Actions Status, Run et Remove
$existingTask = Get-OpenZimScheduledTask
switch ($Action) {
    'Status' {
        Show-OpenZimScheduledTask -Task $existingTask
        return
    }
    'Run' {
        if (-not [string]::IsNullOrWhiteSpace($script:TaskReadError)) {
            throw "Impossible de tester la tache car Windows refuse sa lecture : $script:TaskReadError"
        }
        if ($null -eq $existingTask) {
            throw "La tache '$TaskName' n existe pas. Creez-la avant de la tester."
        }
        if ($PSCmdlet.ShouldProcess($TaskName, 'Lancer maintenant la vraie mise a jour ZIM')) {
            Start-ScheduledTask -InputObject $existingTask
            Start-Sleep -Seconds 1
            Write-Host "Tache lancee : $TaskName" -ForegroundColor Green
            Write-Host 'Elle s execute en arriere-plan et peut durer longtemps selon le catalogue et les telechargements.'
            Write-Host 'Revenez dans Etat / dernier resultat apres sa fin pour connaitre le code final.'
            Show-OpenZimScheduledTask -Task (Get-OpenZimScheduledTask)
        }
        return
    }
    'Remove' {
        if (-not [string]::IsNullOrWhiteSpace($script:TaskReadError)) {
            throw "Impossible de supprimer la tache car Windows refuse sa lecture : $script:TaskReadError"
        }
        if ($null -eq $existingTask) {
            Write-Host "Aucune tache a supprimer : $TaskName" -ForegroundColor Yellow
            return
        }
        if ($PSCmdlet.ShouldProcess($TaskName, 'Supprimer la tache planifiee')) {
            Unregister-ScheduledTask -InputObject $existingTask -Confirm:$false
            Write-Host "Tache supprimee : $TaskName" -ForegroundColor Green
            Write-Host 'Les archives ZIM et les fichiers de configuration ont ete conserves.'
        }
        return
    }
}

if (-not [string]::IsNullOrWhiteSpace($script:TaskReadError)) {
    throw "Impossible de creer ou actualiser la tache car Windows refuse l acces au planificateur : $script:TaskReadError"
}
# endregion Actions Status, Run et Remove

# region Creation ou actualisation de la tache
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
    Write-Host "Frequence         : chaque $DayOfWeek a $($At.ToString('HH:mm'))"
    Write-Host 'Utilisez l action Status pour verifier la prochaine execution et le dernier resultat.'
}
# endregion Creation ou actualisation de la tache
