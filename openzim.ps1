#requires -Version 5.1

<#
Fichier de compatibilite.

Le point d'entree officiel est maintenant Start-OpenZimAssistant.ps1.
Ce relais conserve le fonctionnement des anciennes commandes et raccourcis.
#>

& (Join-Path $PSScriptRoot 'Start-OpenZimAssistant.ps1') @args
exit $LASTEXITCODE
