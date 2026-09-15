#requires -Version 5.1

<#
.SYNOPSIS
Assistant d'installation et de gestion OpenZIM MCP pour Windows.

.DESCRIPTION
Sans parametre, ouvre un menu guide adapte aux debutants. Les utilisateurs
avances peuvent toujours appeler une action directement avec -Action.

Le script orchestre quatre briques distinctes :
- Ollama execute le modele de langage local ;
- GPT-OSS ou Qwen produit les reponses et les appels d'outils ;
- OpenZIM MCP expose les recherches documentaires au client VS Code ;
- les archives ZIM contiennent les connaissances utilisables hors ligne.

.PARAMETER Action
Action a executer sans ouvrir le menu. Sans cette option, le menu interactif
est affiche. Utilisez la touche A dans le menu pour afficher le parcours guide.

.PARAMETER LibraryRoot
Dossier racine qui contient les archives ZIM classees par categorie.

.PARAMETER ProjectDirectory
Dossier racine du projet VS Code a connecter a OpenZIM MCP.

.PARAMETER MaxLibrarySizeGB
Plafond de selection des archives ZIM. Ce plafond n'inclut pas les modeles
Ollama, qui sont geres separement.

.EXAMPLE
.\openzim.ps1

.EXAMPLE
.\openzim.ps1 -Action Plan

.EXAMPLE
.\openzim.ps1 -Action Configure -ProjectDirectory C:\Projets\MonApplication
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath,

    [Parameter()]
    [ValidateSet('Install', 'InstallAI', 'Discover', 'Plan', 'Download', 'Update', 'Configure', 'Status', 'Test', 'RegisterUpdate', 'All')]
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
    [switch] $InstallGptOss,

    [Parameter()]
    [switch] $InstallQwenCoder,

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
$localAiInstaller = Join-Path $PSScriptRoot 'install-local-ai.ps1'
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

function Write-ActionIntroduction {
    param([Parameter(Mandatory)] [string] $RequestedAction)

    $descriptions = @{
        Install        = 'Verification de uv, installation ou mise a jour de OpenZIM MCP, puis test de sa commande.'
        InstallAI      = 'Verification de Ollama et telechargement des seuls modeles selectionnes qui sont absents.'
        Discover       = 'Lecture du catalogue Kiwix pour reperer d autres documentations techniques disponibles.'
        Plan           = 'Calcul du panier ZIM selon la pertinence et le budget. Aucun gros fichier ne sera telecharge.'
        Download       = 'Telechargement des archives du plan avec reprise, controle de taille et verification SHA-256.'
        Update         = 'Comparaison avec le catalogue puis telechargement des editions plus recentes.'
        Configure      = 'Creation de la connexion MCP et des instructions IA dans le projet VS Code selectionne.'
        Status         = 'Inventaire des archives locales, sans acces necessaire a Internet.'
        Test           = 'Diagnostic de la chaine locale. Ce controle ne pose aucune question au modele.'
        RegisterUpdate = 'Creation d une tache Windows qui verifiera les nouvelles archives chaque semaine.'
        All            = 'Parcours complet : composants, plan, confirmation des ZIM, configuration du projet et diagnostic.'
    }
    if ($descriptions.ContainsKey($RequestedAction)) {
        Write-Host "`nACTION : $RequestedAction" -ForegroundColor Cyan
        Write-Host $descriptions[$RequestedAction] -ForegroundColor DarkCyan
    }
}

function Invoke-OpenZimAction {
    param([Parameter(Mandatory)] [string] $RequestedAction)

    Write-ActionIntroduction -RequestedAction $RequestedAction

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
        'InstallAI' {
            Invoke-LocalScript -Path $localAiInstaller -Arguments @{
                GptOss20B   = $InstallGptOss
                QwenCoder14B = $InstallQwenCoder
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
                ForceMcpConfig   = $true
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
    $userProfilePath = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($userProfilePath)) {
        $userProfilePath = $env:USERPROFILE
    }
    $defaultOpenZimPath = if ([string]::IsNullOrWhiteSpace($userProfilePath)) {
        $null
    }
    else {
        Join-Path $userProfilePath '.local\bin\openzim-mcp.exe'
    }
    $openZimStatus = if ($null -ne $openZimCommand) {
        'installe'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($defaultOpenZimPath) -and
        (Test-Path -LiteralPath $defaultOpenZimPath -PathType Leaf)) {
        'installe (PATH a reparer)'
    }
    else {
        'non installe'
    }

    $ollamaCommand = Get-Command ollama.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $ollamaCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $ollamaCandidates += Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $ollamaCandidates += Join-Path $env:ProgramFiles 'Ollama\ollama.exe'
    }
    $ollamaInstalled =
        ($null -ne $ollamaCommand) -or
        (@($ollamaCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -gt 0)

    $vscodeCommand = Get-Command code.cmd, code.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $vscodeCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $vscodeCandidates += Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $vscodeCandidates += Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'
    }
    $programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $vscodeCandidates += Join-Path $programFilesX86 'Microsoft VS Code\Code.exe'
    }
    $vscodeInstalled =
        ($null -ne $vscodeCommand) -or
        (@($vscodeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -gt 0)

    $ollamaModels = @()
    $ollamaApiAvailable = $false
    if ($ollamaInstalled) {
        try {
            $ollamaResponse = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 1
            $ollamaModels = @($ollamaResponse.models | ForEach-Object { [string] $_.name })
            $ollamaApiAvailable = $true
        }
        catch {
            # L'ecran d'accueil reste passif : il ne demarre pas Ollama automatiquement.
        }
    }

    $gptOssStatus = if (-not $ollamaInstalled) {
        'non verifiable (Ollama absent)'
    }
    elseif (-not $ollamaApiAvailable) {
        'non verifiable (service Ollama arrete)'
    }
    elseif ('gpt-oss:20b' -in $ollamaModels) {
        'installe'
    }
    else {
        'non installe'
    }

    $qwenModel = 'qwen2.5-coder:14b-instruct-q5_K_M'
    $qwenStatus = if (-not $ollamaInstalled) {
        'non verifiable (Ollama absent)'
    }
    elseif (-not $ollamaApiAvailable) {
        'non verifiable (service Ollama arrete)'
    }
    elseif ($qwenModel -in $ollamaModels) {
        'installe'
    }
    else {
        'non installe'
    }

    # La lecture porte uniquement sur les metadonnees des fichiers. Aucun ZIM
    # n'est ouvert ni indexe pour construire cet apercu.
    $zimFiles = @(if (Test-Path -LiteralPath $LibraryRoot -PathType Container) {
        Get-ChildItem -LiteralPath $LibraryRoot -Filter '*.zim' -File -Recurse -ErrorAction SilentlyContinue
    })
    $zimBytes = ($zimFiles | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $zimBytes) { $zimBytes = 0 }
    $zimStatus = '{0} archive(s), {1:N2} Go' -f $zimFiles.Count, ($zimBytes / 1GB)

    $mcpConfigurationPath = Join-Path $ProjectDirectory '.vscode\mcp.json'
    $agentInstructionsPath = Join-Path $ProjectDirectory '.github\copilot-instructions.md'
    $projectConfigured =
        (Test-Path -LiteralPath $mcpConfigurationPath -PathType Leaf) -and
        (Test-Path -LiteralPath $agentInstructionsPath -PathType Leaf)

    $checks = @(
        @{ Name = 'PowerShell'; Present = $PSVersionTable.PSVersion.ToString() }
        @{ Name = 'WinGet'; Present = if (Get-Command winget.exe -ErrorAction SilentlyContinue) { 'detecte' } else { 'absent' } }
        @{ Name = 'uv'; Present = if (Get-Command uv.exe -ErrorAction SilentlyContinue) { 'installe' } else { 'non installe' } }
        @{ Name = 'OpenZIM MCP'; Present = $openZimStatus }
        @{ Name = 'Visual Studio Code'; Present = if ($vscodeInstalled) { 'installe' } else { 'non detecte' } }
        @{ Name = 'Ollama'; Present = if ($ollamaInstalled) { 'installe' } else { 'non detecte' } }
        @{ Name = 'GPT-OSS 20B'; Present = $gptOssStatus }
        @{ Name = 'Qwen2.5-Coder 14B'; Present = $qwenStatus }
        @{ Name = 'Archives ZIM'; Present = $zimStatus }
        @{ Name = 'Projet VS Code'; Present = if ($projectConfigured) { 'configure pour OpenZIM' } else { 'a configurer (option 5)' } }
    )
    Write-Host 'Etat rapide :' -ForegroundColor Cyan
    foreach ($check in $checks) {
        Write-Host ('  {0,-22} {1}' -f $check.Name, $check.Present)
    }

    $recommendation = if ($openZimStatus -eq 'non installe') {
        'Commencez par l option 2 pour installer OpenZIM MCP.'
    }
    elseif (-not $ollamaInstalled -or ($gptOssStatus -ne 'installe' -and $qwenStatus -ne 'installe')) {
        'Utilisez l option 12 pour installer Ollama et choisir au moins un modele.'
    }
    elseif ($zimFiles.Count -eq 0) {
        'Utilisez d abord l option 3 pour voir le panier, puis l option 4 pour le telecharger.'
    }
    elseif (-not $projectConfigured) {
        'Utilisez l option 5 pour connecter votre projet VS Code a la base documentaire.'
    }
    else {
        'La chaine semble prete. Lancez l option 6, puis testez une recherche dans le chat VS Code.'
    }
    Write-Host "`nConseil : $recommendation" -ForegroundColor Yellow
}

function Show-BeginnerHelp {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host '       COMPRENDRE VOTRE AGENT IA LOCAL' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host @'

COMMENT LES COMPOSANTS TRAVAILLENT ENSEMBLE

  VS Code et son extension de chat
       | envoie votre question au modele et autorise les outils MCP
       v
  Ollama -> GPT-OSS 20B ou Qwen2.5-Coder
       | demande une recherche documentaire quand elle est utile
       v
  OpenZIM MCP -> archives .zim Kiwix stockees sur votre disque

Ollama execute le modele. Le modele ne lit pas directement les fichiers ZIM :
le client de chat doit prendre en charge MCP et lui permettre d appeler
OpenZIM. L option 5 prepare automatiquement les fichiers du projet.

PARCOURS RECOMMANDE POUR UNE PREMIERE INSTALLATION

  1. Option 1 : choisir le dossier, le budget ZIM et le mode simple.
  2. Option 12 : installer Ollama et au moins un modele local.
  3. Option 2 : installer uv et le serveur OpenZIM MCP.
  4. Option 3 : examiner le panier documentaire sans telecharger.
  5. Option 4 : confirmer et telecharger les archives selectionnees.
  6. Option 5 : saisir le dossier racine de votre projet VS Code.
  7. Option 6 : verifier l ensemble, puis recharger la fenetre VS Code.

FICHIERS CREES DANS CHAQUE PROJET

  .vscode\mcp.json                  connexion au serveur OpenZIM
  .github\copilot-instructions.md   consigne de consulter la base locale

Le budget ZIM ne comprend pas les modeles Ollama. Comptez environ 14 Go pour
GPT-OSS 20B et 11 Go pour Qwen2.5-Coder 14B Q5_K_M, en plus des archives.

Aucune option de planification ou de statut ne telecharge de gros fichier.
Les options 4, 8, 11 et 12 annoncent ou demandent confirmation avant les
telechargements importants.
'@
}

function Start-LocalAiWizard {
    Write-Host "`nINSTALLATION DU MOTEUR IA LOCAL" -ForegroundColor Cyan
    Write-Host 'Ollama sera installe uniquement s il est absent.'
    Write-Host 'Les modeles deja presents ne seront pas telecharges une seconde fois.'
    Write-Host ''
    $script:InstallGptOss = Read-YesNo `
        -Prompt 'Installer GPT-OSS 20B (environ 14 Go)' `
        -Default $true
    $script:InstallQwenCoder = Read-YesNo `
        -Prompt 'Installer Qwen2.5-Coder 14B Q5_K_M (environ 11 Go)' `
        -Default $false
    Invoke-OpenZimAction -RequestedAction 'InstallAI'
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
        Write-Host "Projet actif  : $ProjectDirectory"
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
        Write-Host ' 12. Installer Ollama et les modeles IA locaux'
        Write-Host ' 13. Quitter'
        Write-Host '  A. Aide : comprendre le parcours complet'

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
                    if (Read-YesNo -Prompt 'Installer ou verifier aussi Ollama et les modeles locaux' -Default $true) {
                        Start-LocalAiWizard
                    }
                    Invoke-OpenZimAction -RequestedAction 'All'
                }
                '12' { Start-LocalAiWizard }
                '13' { return }
                '0' { return }
                { $_ -in @('a', 'aide', 'help', '?') } { Show-BeginnerHelp }
                default { Write-Host 'Choix invalide.' -ForegroundColor Yellow }
            }
        }
        catch {
            Write-Host "`nERREUR : $($_.Exception.Message)" -ForegroundColor Red
            Write-Host 'Consultez le dossier .logs pour les details si une operation de bibliotheque avait commence.'
        }
        if ($choice -notin @('0', '13')) {
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
