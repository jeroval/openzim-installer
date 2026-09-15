#requires -Version 5.1

<#
.SYNOPSIS
Assistant d'installation et de gestion OpenZIM MCP pour Windows.

.DESCRIPTION
Sans parametre, ouvre un menu guide adapte aux debutants. Les utilisateurs
avances peuvent toujours appeler une action directement avec -Action.

.EXAMPLE
.\openzim.ps1

.EXAMPLE
.\openzim.ps1 -Action Plan
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath,

    [Parameter()]
    [ValidateSet('Install', 'Discover', 'Plan', 'Download', 'Update', 'Configure', 'Status', 'Test', 'RegisterUpdate', 'All')]
    [string] $Action,

    [Parameter()]
    [string] $LibraryRoot,

    [Parameter()]
    [string] $ProjectDirectory = (Get-Location).Path,

    [Parameter()]
    [ValidateSet('simple', 'advanced')]
    [string] $Mode,

    [Parameter()]
    [switch] $IncludeOptional,

    [Parameter()]
    [switch] $WithReranker,

    [Parameter()]
    [switch] $RemovePrevious,

    [Parameter()]
    [int] $MaxLibrarySizeGB,

    [Parameter()]
    [switch] $AllowBudgetOverflow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:InvocationParameters = @{} + $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'openzim.config.json'
}

$installer = Join-Path $PSScriptRoot 'install-openzim-mcp.ps1'
$manager = Join-Path $PSScriptRoot 'manage-zim-library.ps1'
$tester = Join-Path $PSScriptRoot 'test-local-agent.ps1'
$scheduler = Join-Path $PSScriptRoot 'register-zim-update-task.ps1'

function Expand-ConfiguredPath {
    param([Parameter(Mandatory)] [string] $Path)
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Read-OpenZimConfiguration {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration introuvable : $ConfigPath"
    }
    try {
        return Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Le fichier de configuration est invalide. Relancez l'assistant ou restaurez '$ConfigPath'."
    }
}

function Save-OpenZimConfiguration {
    param([Parameter(Mandatory)] [object] $Configuration)

    $temporaryPath = "$ConfigPath.tmp"
    $Configuration | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $ConfigPath -Force
}

function Read-ValueWithDefault {
    param([string] $Prompt, [string] $Default)
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }
    return $answer.Trim()
}

function Read-YesNo {
    param([string] $Prompt, [bool] $Default = $false)
    $suffix = if ($Default) { '[O/n]' } else { '[o/N]' }
    while ($true) {
        $rawAnswer = Read-Host "$Prompt $suffix"
        $answer = if ($null -eq $rawAnswer) { '' } else { $rawAnswer.Trim().ToLowerInvariant() }
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer -in @('o', 'oui', 'y', 'yes')) { return $true }
        if ($answer -in @('n', 'non', 'no')) { return $false }
        Write-Host 'Repondez par O pour oui ou N pour non.' -ForegroundColor Yellow
    }
}

function Pause-OpenZim {
    if ([Environment]::UserInteractive) {
        [void] (Read-Host "`nAppuyez sur Entree pour continuer")
    }
}

function Initialize-EffectiveSettings {
    $script:configuration = Read-OpenZimConfiguration
    if (-not $script:InvocationParameters.ContainsKey('LibraryRoot')) {
        $script:LibraryRoot = Expand-ConfiguredPath ([string] $configuration.libraryRoot)
    }
    if (-not $script:InvocationParameters.ContainsKey('Mode')) {
        $script:Mode = [string] $configuration.mode
    }
    if (-not $script:InvocationParameters.ContainsKey('MaxLibrarySizeGB')) {
        $script:MaxLibrarySizeGB = [int] $configuration.maxLibrarySizeGB
    }
    if (-not $script:InvocationParameters.ContainsKey('IncludeOptional') -and [bool] $configuration.includeOptional) {
        $script:IncludeOptional = $true
    }
    if ($MaxLibrarySizeGB -lt 1 -or $MaxLibrarySizeGB -gt 4096) {
        throw 'La limite de bibliotheque doit etre comprise entre 1 et 4096 Go.'
    }
    if ($Mode -notin @('simple', 'advanced')) {
        throw "Mode MCP invalide : $Mode"
    }
}

function Invoke-LocalScript {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter()] [hashtable] $Arguments = @{}
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Script requis introuvable : $Path"
    }
    if ($WhatIfPreference -and $Path -ne $tester) {
        $Arguments.WhatIf = $true
    }
    & $Path @Arguments
}

function Invoke-OpenZimAction {
    param([Parameter(Mandatory)] [string] $RequestedAction)

    $commonManagerArguments = @{
        ConfigPath           = $ConfigPath
        LibraryRoot          = $LibraryRoot
        IncludeOptional      = $IncludeOptional
        RemovePrevious       = $RemovePrevious
        MaxLibrarySizeGB     = $MaxLibrarySizeGB
        AllowBudgetOverflow  = $AllowBudgetOverflow
        Confirm              = $false
    }

    switch ($RequestedAction) {
        'Install' {
            Invoke-LocalScript -Path $installer -Arguments @{
                WithReranker = $WithReranker
                Confirm      = $false
            }
        }
        'Plan' {
            $arguments = $commonManagerArguments.Clone()
            $arguments['Action'] = 'Plan'
            Invoke-LocalScript -Path $manager -Arguments $arguments
        }
        'Discover' {
            $arguments = $commonManagerArguments.Clone()
            $arguments['Action'] = 'Discover'
            Invoke-LocalScript -Path $manager -Arguments $arguments
        }
        'Download' {
            $arguments = $commonManagerArguments.Clone()
            $arguments['Action'] = 'Download'
            Invoke-LocalScript -Path $manager -Arguments $arguments
        }
        'Update' {
            $arguments = $commonManagerArguments.Clone()
            $arguments['Action'] = 'Update'
            Invoke-LocalScript -Path $manager -Arguments $arguments
        }
        'Configure' {
            Invoke-LocalScript -Path $installer -Arguments @{
                ZimDirectory     = $LibraryRoot
                ConfigureVSCode  = $true
                ProjectDirectory = $ProjectDirectory
                Mode             = $Mode
                Confirm          = $false
            }
        }
        'Status' {
            Invoke-LocalScript -Path $manager -Arguments @{
                ConfigPath  = $ConfigPath
                Action      = 'Status'
                LibraryRoot = $LibraryRoot
            }
        }
        'Test' {
            Invoke-LocalScript -Path $tester -Arguments @{
                LibraryRoot      = $LibraryRoot
                ProjectDirectory = $ProjectDirectory
            }
        }
        'RegisterUpdate' {
            Invoke-LocalScript -Path $scheduler -Arguments @{
                ConfigPath      = $ConfigPath
                LibraryRoot     = $LibraryRoot
                IncludeOptional = $IncludeOptional
                RemovePrevious  = $RemovePrevious
                Confirm         = $false
            }
        }
        'All' {
            Invoke-OpenZimAction -RequestedAction 'Install'
            Invoke-OpenZimAction -RequestedAction 'Plan'
            if (Read-YesNo -Prompt 'Le plan vous convient-il ? Lancer les telechargements maintenant') {
                Invoke-OpenZimAction -RequestedAction 'Download'
                Invoke-OpenZimAction -RequestedAction 'Configure'
                Invoke-OpenZimAction -RequestedAction 'Test'
            }
        }
    }
}

function Show-EnvironmentSummary {
    $openZimCommand = Get-Command openzim-mcp.exe -ErrorAction SilentlyContinue
    $defaultOpenZimPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local\bin\openzim-mcp.exe'
    $openZimStatus = if ($null -ne $openZimCommand) {
        'installe'
    }
    elseif (Test-Path -LiteralPath $defaultOpenZimPath -PathType Leaf) {
        'installe (PATH a reparer)'
    }
    else {
        'non installe'
    }

    $checks = @(
        @{ Name = 'PowerShell'; Present = $PSVersionTable.PSVersion.ToString() }
        @{ Name = 'WinGet'; Present = if (Get-Command winget.exe -ErrorAction SilentlyContinue) { 'detecte' } else { 'absent' } }
        @{ Name = 'uv'; Present = if (Get-Command uv.exe -ErrorAction SilentlyContinue) { 'installe' } else { 'non installe' } }
        @{ Name = 'OpenZIM MCP'; Present = $openZimStatus }
        @{ Name = 'Ollama'; Present = if (Get-Command ollama.exe -ErrorAction SilentlyContinue) { 'installe' } else { 'non detecte' } }
    )
    Write-Host 'Etat rapide :' -ForegroundColor Cyan
    foreach ($check in $checks) {
        Write-Host ('  {0,-14} {1}' -f $check.Name, $check.Present)
    }
}

function Start-ConfigurationWizard {
    Write-Host "`nCONFIGURATION ASSISTEE" -ForegroundColor Cyan
    Write-Host 'Appuyez simplement sur Entree pour conserver une valeur proposee.'

    $currentRoot = Expand-ConfiguredPath ([string] $configuration.libraryRoot)
    $newRoot = Read-ValueWithDefault -Prompt 'Dossier des archives ZIM' -Default $currentRoot

    while ($true) {
        $budgetText = Read-ValueWithDefault -Prompt 'Taille maximale de la bibliotheque en Go' -Default ([string] $configuration.maxLibrarySizeGB)
        $parsedBudget = 0
        if ([int]::TryParse($budgetText, [ref] $parsedBudget) -and $parsedBudget -ge 1 -and $parsedBudget -le 4096) {
            break
        }
        Write-Host 'Saisissez un nombre entier compris entre 1 et 4096.' -ForegroundColor Yellow
    }

    Write-Host "Le panier sera adapte automatiquement au plafond de $parsedBudget Go." -ForegroundColor DarkCyan
    Write-Host 'Un budget plus eleve debloque des collections plus riches lorsqu elles sont disponibles.' -ForegroundColor DarkCyan

    $includeExtra = Read-YesNo -Prompt 'Inclure Dart, Bootstrap et les sources optionnelles' -Default ([bool] $configuration.includeOptional)
    $advancedMode = Read-YesNo -Prompt 'Activer le mode MCP avance (simple recommande pour debuter)' -Default ([string] $configuration.mode -eq 'advanced')

    $configuration.libraryRoot = $newRoot
    $configuration.maxLibrarySizeGB = $parsedBudget
    $configuration.includeOptional = $includeExtra
    $configuration.mode = if ($advancedMode) { 'advanced' } else { 'simple' }
    Save-OpenZimConfiguration -Configuration $configuration
    Initialize-EffectiveSettings

    Write-Host "`nConfiguration enregistree automatiquement." -ForegroundColor Green
    Write-Host "Bibliotheque : $LibraryRoot"
    Write-Host "Budget        : $MaxLibrarySizeGB Go"
    Write-Host "Mode MCP      : $Mode"
}

function Start-BeginnerMenu {
    while ($true) {
        Clear-Host
        Write-Host '============================================================' -ForegroundColor DarkCyan
        Write-Host '       ASSISTANT OPENZIM MCP POUR AGENT IA LOCAL' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkCyan
        Write-Host "Bibliotheque : $LibraryRoot"
        Write-Host "Budget        : $MaxLibrarySizeGB Go | Mode MCP : $Mode"
        Write-Host ''
        Show-EnvironmentSummary
        Write-Host ''
        Write-Host '  1. Configuration assistee'
        Write-Host '  2. Installer ou mettre a jour OpenZIM MCP'
        Write-Host '  3. Voir le plan de telechargement (aucun gros fichier)'
        Write-Host '  4. Telecharger le pack ZIM selectionne'
        Write-Host '  5. Configurer OpenZIM MCP dans un projet VS Code'
        Write-Host '  6. Verifier toute l installation'
        Write-Host '  7. Afficher les archives deja installees'
        Write-Host '  8. Rechercher et telecharger les mises a jour'
        Write-Host '  9. Decouvrir d autres documentations Kiwix'
        Write-Host ' 10. Programmer une mise a jour hebdomadaire'
        Write-Host ' 11. Installation guidee complete'
        Write-Host '  0. Quitter'

        $rawChoice = Read-Host "`nVotre choix"
        $choice = if ($null -eq $rawChoice) { '' } else { $rawChoice.Trim() }
        try {
            switch ($choice) {
                '1' { Start-ConfigurationWizard }
                '2' { Invoke-OpenZimAction -RequestedAction 'Install' }
                '3' { Invoke-OpenZimAction -RequestedAction 'Plan' }
                '4' {
                    Write-Host "`nCette operation peut telecharger plusieurs gigaoctets." -ForegroundColor Yellow
                    if (Read-YesNo -Prompt "Confirmer le telechargement avec une limite de $MaxLibrarySizeGB Go") {
                        Invoke-OpenZimAction -RequestedAction 'Download'
                    }
                }
                '5' {
                    $defaultProject = $ProjectDirectory
                    $selectedProject = Read-ValueWithDefault -Prompt 'Dossier du projet VS Code' -Default $defaultProject
                    if (-not (Test-Path -LiteralPath $selectedProject -PathType Container)) {
                        throw "Dossier de projet introuvable : $selectedProject"
                    }
                    $script:ProjectDirectory = (Resolve-Path -LiteralPath $selectedProject).Path
                    Invoke-OpenZimAction -RequestedAction 'Configure'
                }
                '6' { Invoke-OpenZimAction -RequestedAction 'Test' }
                '7' { Invoke-OpenZimAction -RequestedAction 'Status' }
                '8' {
                    if (Read-YesNo -Prompt 'Verifier le catalogue et telecharger les nouvelles versions') {
                        Invoke-OpenZimAction -RequestedAction 'Update'
                    }
                }
                '9' { Invoke-OpenZimAction -RequestedAction 'Discover' }
                '10' {
                    if (Read-YesNo -Prompt 'Creer une tache de mise a jour chaque dimanche a 03:00') {
                        Invoke-OpenZimAction -RequestedAction 'RegisterUpdate'
                    }
                }
                '11' {
                    $selectedProject = Read-ValueWithDefault -Prompt 'Dossier du projet VS Code a configurer' -Default $ProjectDirectory
                    if (-not (Test-Path -LiteralPath $selectedProject -PathType Container)) {
                        throw "Dossier de projet introuvable : $selectedProject"
                    }
                    $script:ProjectDirectory = (Resolve-Path -LiteralPath $selectedProject).Path
                    Invoke-OpenZimAction -RequestedAction 'All'
                }
                '0' { return }
                default { Write-Host 'Choix invalide.' -ForegroundColor Yellow }
            }
        }
        catch {
            Write-Host "`nERREUR : $($_.Exception.Message)" -ForegroundColor Red
            Write-Host 'Consultez le dossier .logs pour les details si une operation de bibliotheque avait commence.'
        }
        if ($choice -ne '0') {
            Pause-OpenZim
        }
    }
}

Initialize-EffectiveSettings
if ([string]::IsNullOrWhiteSpace($Action)) {
    Start-BeginnerMenu
}
else {
    Invoke-OpenZimAction -RequestedAction $Action
}
