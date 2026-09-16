#requires -Version 5.1

<#
Fichier de compatibilite pour les anciennes taches Windows.

Le script officiel est maintenant scripts\Invoke-ZimScheduledTask.ps1.
Conservez ce relais tant qu'une ancienne tache planifiee peut encore le viser.
#>

& (Join-Path $PSScriptRoot 'scripts\Invoke-ZimScheduledTask.ps1') @args
exit $LASTEXITCODE
