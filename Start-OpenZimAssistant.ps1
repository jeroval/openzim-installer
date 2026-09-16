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
.\Start-OpenZimAssistant.ps1

.EXAMPLE
.\Start-OpenZimAssistant.ps1 -Action Plan

.EXAMPLE
.\Start-OpenZimAssistant.ps1 -Action Configure -ProjectDirectory C:\Projets\MonApplication
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
    [ValidateSet('general', 'web', 'systems', 'data-ai', 'security')]
    [string] $UsageProfile,

    [Parameter()]
    [switch] $IncludeOptional,

    [Parameter()]
    [switch] $WithReranker,

    [Parameter()]
    [switch] $InstallGptOss,

    [Parameter()]
    [switch] $InstallQwenCoder,

    [Parameter()]
    [ValidateSet('Create', 'Status', 'Run', 'Remove')]
    [string] $ScheduledTaskOperation = 'Create',

    [Parameter()]
    [switch] $RemovePrevious,

    [Parameter()]
    [int] $MaxLibrarySizeGB,

    [Parameter()]
    [switch] $AllowBudgetOverflow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# region Initialisation et chemins internes
# Tous les chemins du depot sont declares ici. Les fonctions suivantes ne
# reconstruisent jamais l'arborescence elles-memes.
$script:InvocationParameters = @{} + $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'config\OpenZim.Settings.json'
}

$scriptsDirectory = Join-Path $PSScriptRoot 'scripts'
$installer = Join-Path $scriptsDirectory 'Install-OpenZimMcp.ps1'
$localAiInstaller = Join-Path $scriptsDirectory 'Install-LocalAi.ps1'
$manager = Join-Path $scriptsDirectory 'Invoke-ZimLibrary.ps1'
$tester = Join-Path $scriptsDirectory 'Test-LocalAgent.ps1'
$scheduler = Join-Path $scriptsDirectory 'Invoke-ZimScheduledTask.ps1'
$scheduledTaskName = 'Local AI - Update Kiwix ZIM Library'
# endregion Initialisation et chemins internes

# region Configuration et saisie utilisateur
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

function Get-UsageProfileLabel {
    param([Parameter(Mandatory)] [string] $Profile)

    $labels = @{
        general  = 'Developpement polyvalent'
        web      = 'Web et applications'
        systems  = 'Systemes, reseaux et DevOps'
        'data-ai' = 'Donnees et intelligence artificielle'
        security = 'Securite informatique'
    }
    if ($labels.ContainsKey($Profile)) { return $labels[$Profile] }
    return $Profile
}

function Get-AvailableSpaceGB {
    param([Parameter(Mandatory)] [string] $Path)

    $expandedPath = Expand-ConfiguredPath $Path
    $probePath = $expandedPath
    while (-not [string]::IsNullOrWhiteSpace($probePath) -and
        -not (Test-Path -LiteralPath $probePath -PathType Container)) {
        $parent = Split-Path -Parent $probePath
        if ($parent -eq $probePath) { break }
        $probePath = $parent
    }
    if ([string]::IsNullOrWhiteSpace($probePath) -or
        -not (Test-Path -LiteralPath $probePath -PathType Container)) {
        return $null
    }

    $root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $probePath).Path)
    $driveName = $root.TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    if ($null -eq $drive -or $null -eq $drive.Free) { return $null }
    return [math]::Round(($drive.Free / 1GB), 1)
}

function Initialize-EffectiveSettings {
    $script:configuration = Read-OpenZimConfiguration
    if (-not $script:InvocationParameters.ContainsKey('LibraryRoot')) {
        $script:LibraryRoot = Expand-ConfiguredPath ([string] $configuration.libraryRoot)
    }
    if (-not $script:InvocationParameters.ContainsKey('Mode')) {
        $script:Mode = [string] $configuration.mode
    }
    if (-not $script:InvocationParameters.ContainsKey('UsageProfile')) {
        $script:UsageProfile = if ($null -ne $configuration.PSObject.Properties['usageProfile']) {
            [string] $configuration.usageProfile
        }
        else {
            'general'
        }
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
    if ($UsageProfile -notin @('general', 'web', 'systems', 'data-ai', 'security')) {
        throw "Profil d usage invalide : $UsageProfile"
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
# endregion Configuration et saisie utilisateur

# region Orchestration des actions
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
        UsageProfile         = $UsageProfile
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
                Action          = $ScheduledTaskOperation
                ConfigPath      = $ConfigPath
                TaskName        = $scheduledTaskName
                LibraryRoot     = $LibraryRoot
                IncludeOptional = $IncludeOptional
                RemovePrevious  = $RemovePrevious
                Confirm         = $false
            }
        }
        'All' {
            Write-Host "`nETAPE 1/5 - Verifier le pont documentaire" -ForegroundColor Magenta
            Invoke-OpenZimAction -RequestedAction 'Install'
            Write-Host "`nETAPE 2/5 - Prototyper votre bibliotheque" -ForegroundColor Magenta
            Invoke-OpenZimAction -RequestedAction 'Plan'
            Write-Host 'Le plan est une previsualisation : vous pouvez revenir a l option 1 pour changer le besoin ou le budget.' -ForegroundColor DarkCyan
            if (Read-YesNo -Prompt 'Ce prototype vous convient-il ? Lancer les telechargements maintenant') {
                Write-Host "`nETAPE 3/5 - Construire la base documentaire" -ForegroundColor Magenta
                Invoke-OpenZimAction -RequestedAction 'Download'
                Write-Host "`nETAPE 4/5 - Connecter votre projet et ses instructions" -ForegroundColor Magenta
                Invoke-OpenZimAction -RequestedAction 'Configure'
                Write-Host "`nETAPE 5/5 - Valider l experience de bout en bout" -ForegroundColor Magenta
                Invoke-OpenZimAction -RequestedAction 'Test'
            }
            else {
                Write-Host 'Parcours interrompu avant tout gros telechargement. Votre configuration est conservee.' -ForegroundColor Yellow
            }
        }
    }
}
# endregion Orchestration des actions

# region Interface du menu guide
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

    $scheduledTask = $null
    $scheduledTaskStatus = 'non configuree (option 10)'
    try {
        $scheduledTask = Get-ScheduledTask -TaskName $scheduledTaskName -ErrorAction Stop |
            Where-Object TaskName -EQ $scheduledTaskName |
            Select-Object -First 1
        if ($null -ne $scheduledTask) {
            $scheduledTaskStatus = "installee ($($scheduledTask.State))"
        }
    }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'CmdletizationQuery_NotFound*' -and
            $_.Exception.Message -notmatch 'No MSFT_ScheduledTask|introuvable|not found') {
            $scheduledTaskStatus = 'non verifiable (acces Windows refuse)'
        }
    }

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
        @{ Name = 'Mise a jour auto'; Present = $scheduledTaskStatus }
    )
    Write-Host 'Etat rapide :' -ForegroundColor Cyan
    foreach ($check in $checks) {
        Write-Host ('  {0,-22} {1}' -f $check.Name, $check.Present)
    }

    $hasModel = $gptOssStatus -eq 'installe' -or $qwenStatus -eq 'installe'
    $journey = @(
        @{ Label = 'Moteur IA local'; Done = $ollamaInstalled -and $hasModel }
        @{ Label = 'Serveur OpenZIM MCP'; Done = $openZimStatus -eq 'installe' }
        @{ Label = 'Base documentaire ZIM'; Done = $zimFiles.Count -gt 0 }
        @{ Label = 'Projet VS Code connecte'; Done = $projectConfigured }
    )
    $completedSteps = @($journey | Where-Object Done).Count
    Write-Host "`nVotre parcours : $completedSteps/$($journey.Count) etapes pretes" -ForegroundColor Cyan
    foreach ($step in $journey) {
        $marker = if ($step.Done) { '[OK]' } else { '[A FAIRE]' }
        $color = if ($step.Done) { 'Green' } else { 'Yellow' }
        Write-Host ('  {0,-10} {1}' -f $marker, $step.Label) -ForegroundColor $color
    }

    $recommendation = if ($openZimStatus -ne 'installe') {
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

  1. Option 1 : exprimer votre usage, votre dossier, votre budget et votre mode.
  2. Option 12 : installer Ollama et au moins un modele local.
  3. Option 2 : installer uv et le serveur OpenZIM MCP.
  4. Option 3 : examiner le panier documentaire sans telecharger.
  5. Option 4 : confirmer et telecharger les archives selectionnees.
  6. Option 5 : saisir le dossier racine de votre projet VS Code.
  7. Option 6 : verifier l ensemble, puis recharger la fenetre VS Code.

FICHIERS CREES DANS CHAQUE PROJET

  .vscode\mcp.json                  connexion au serveur OpenZIM
  .github\copilot-instructions.md   consigne de consulter la base locale
  .github\instructions\...          standards appliques a tous les fichiers
  docs\ai\Guide-Bonnes-Pratiques-Code.md  guide complet partage
  AGENTS.md                           politique commune des agents

Le profil d usage modifie l ordre de priorite des sources lorsqu elles ne
tiennent pas toutes dans le budget. Le plan reste visible avant telechargement.

Le budget ZIM ne comprend pas les modeles Ollama. Comptez environ 14 Go pour
GPT-OSS 20B et 11 Go pour Qwen2.5-Coder 14B Q5_K_M, en plus des archives.

Aucune option de planification ou de statut ne telecharge de gros fichier.
Les options 4, 8, 11 et 12 annoncent ou demandent confirmation avant les
telechargements importants.
'@
}

function Start-ScheduledTaskManager {
    while ($true) {
        Clear-Host
        Write-Host '============================================================' -ForegroundColor DarkCyan
        Write-Host '       GESTION DE LA MISE A JOUR PLANIFIEE' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkCyan
        Write-Host 'Cette tache verifie le catalogue Kiwix chaque dimanche a 03:00.'
        Write-Host 'La suppression retire uniquement la tache Windows : vos ZIM sont conserves.'

        & $scheduler `
            -Action Status `
            -ConfigPath $ConfigPath `
            -TaskName $scheduledTaskName `
            -LibraryRoot $LibraryRoot

        Write-Host ''
        Write-Host '  1. Creer ou actualiser la tache hebdomadaire'
        Write-Host '  2. Actualiser l etat et le dernier resultat'
        Write-Host '  3. Lancer maintenant pour tester (vraie mise a jour)'
        Write-Host '  4. Supprimer la tache planifiee'
        Write-Host '  0. Retour au menu principal'

        $scheduleChoice = (Read-Host "`nVotre choix").Trim()
        switch ($scheduleChoice) {
            '1' {
                if (Read-YesNo -Prompt 'Creer ou remplacer la tache du dimanche a 03:00' -Default $true) {
                    $script:ScheduledTaskOperation = 'Create'
                    Invoke-OpenZimAction -RequestedAction 'RegisterUpdate'
                }
            }
            '2' {
                $script:ScheduledTaskOperation = 'Status'
                Invoke-OpenZimAction -RequestedAction 'RegisterUpdate'
            }
            '3' {
                Write-Host "`nATTENTION : ce test execute la vraie recherche de mises a jour." -ForegroundColor Yellow
                Write-Host 'De nouvelles archives peuvent etre telechargees si elles sont disponibles.' -ForegroundColor Yellow
                if (Read-YesNo -Prompt 'Lancer la tache maintenant') {
                    $script:ScheduledTaskOperation = 'Run'
                    Invoke-OpenZimAction -RequestedAction 'RegisterUpdate'
                }
            }
            '4' {
                if (Read-YesNo -Prompt 'Supprimer la tache Windows tout en conservant les archives') {
                    $script:ScheduledTaskOperation = 'Remove'
                    Invoke-OpenZimAction -RequestedAction 'RegisterUpdate'
                }
            }
            '0' { return }
            default { Write-Host 'Choix invalide.' -ForegroundColor Yellow }
        }
        if ($scheduleChoice -ne '0') {
            Pause-OpenZim
        }
    }
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
    Write-Host "`nDEFINIR VOS BESOINS ET VOS CONTRAINTES" -ForegroundColor Cyan
    Write-Host 'Ces reponses personnalisent le panier documentaire. Aucun telechargement ne commence ici.'
    Write-Host 'Appuyez simplement sur Entree pour conserver une valeur proposee.'

    Write-Host "`nQuel usage correspond le mieux a vos projets ?" -ForegroundColor DarkCyan
    Write-Host '  1. Developpement polyvalent (recommande si vous hesitez)'
    Write-Host '  2. Web et applications'
    Write-Host '  3. Systemes, reseaux et DevOps'
    Write-Host '  4. Donnees et intelligence artificielle'
    Write-Host '  5. Securite informatique'
    $profileByChoice = @{
        '1' = 'general'
        '2' = 'web'
        '3' = 'systems'
        '4' = 'data-ai'
        '5' = 'security'
    }
    $currentProfile = if ($null -ne $configuration.PSObject.Properties['usageProfile']) {
        [string] $configuration.usageProfile
    }
    else {
        'general'
    }
    $defaultProfileChoice = (@{
        general = '1'; web = '2'; systems = '3'; 'data-ai' = '4'; security = '5'
    })[$currentProfile]
    while ($true) {
        $profileChoice = Read-ValueWithDefault -Prompt 'Votre profil' -Default $defaultProfileChoice
        if ($profileByChoice.ContainsKey($profileChoice)) {
            $selectedProfile = $profileByChoice[$profileChoice]
            break
        }
        Write-Host 'Choisissez un nombre entre 1 et 5.' -ForegroundColor Yellow
    }

    $currentRoot = Expand-ConfiguredPath ([string] $configuration.libraryRoot)
    $newRoot = Read-ValueWithDefault -Prompt 'Dossier des archives ZIM' -Default $currentRoot

    $availableSpaceGB = Get-AvailableSpaceGB -Path $newRoot
    if ($null -ne $availableSpaceGB) {
        Write-Host "Espace actuellement disponible sur ce disque : $availableSpaceGB Go" -ForegroundColor DarkCyan
    }

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
    if ($null -ne $availableSpaceGB -and $parsedBudget + 5 -gt $availableSpaceGB) {
        Write-Host "ATTENTION : ce budget et la marge de securite de 5 Go depassent l espace actuellement disponible." -ForegroundColor Yellow
        Write-Host 'Le telechargement effectuera un nouveau controle avant toute ecriture.' -ForegroundColor Yellow
    }

    $includeExtra = Read-YesNo -Prompt 'Inclure Dart, Bootstrap et les sources optionnelles' -Default ([bool] $configuration.includeOptional)
    $advancedMode = Read-YesNo -Prompt 'Activer le mode MCP avance (simple recommande pour debuter)' -Default ([string] $configuration.mode -eq 'advanced')

    $selectedMode = if ($advancedMode) { 'advanced' } else { 'simple' }
    Write-Host "`nRESUME DE VOTRE SCENARIO" -ForegroundColor Cyan
    Write-Host "  Usage         : $(Get-UsageProfileLabel -Profile $selectedProfile)"
    Write-Host "  Bibliotheque  : $newRoot"
    Write-Host "  Budget ZIM    : $parsedBudget Go"
    Write-Host "  Sources extra : $(if ($includeExtra) { 'oui' } else { 'non' })"
    Write-Host "  Mode MCP      : $selectedMode"
    if (-not (Read-YesNo -Prompt 'Enregistrer cette configuration' -Default $true)) {
        Write-Host 'Configuration inchangee.' -ForegroundColor Yellow
        return
    }

    $configuration.libraryRoot = $newRoot
    $configuration.maxLibrarySizeGB = $parsedBudget
    $configuration.includeOptional = $includeExtra
    $configuration.mode = $selectedMode
    if ($null -eq $configuration.PSObject.Properties['usageProfile']) {
        $configuration | Add-Member -NotePropertyName usageProfile -NotePropertyValue $selectedProfile
    }
    else {
        $configuration.usageProfile = $selectedProfile
    }
    Save-OpenZimConfiguration -Configuration $configuration
    Initialize-EffectiveSettings

    Write-Host "`nConfiguration enregistree automatiquement." -ForegroundColor Green
    Write-Host "Bibliotheque : $LibraryRoot"
    Write-Host "Budget        : $MaxLibrarySizeGB Go"
    Write-Host "Mode MCP      : $Mode"
    Write-Host "Usage         : $(Get-UsageProfileLabel -Profile $UsageProfile)"
}

function Start-BeginnerMenu {
    while ($true) {
        Clear-Host
        Write-Host '============================================================' -ForegroundColor DarkCyan
        Write-Host '       ASSISTANT OPENZIM MCP POUR AGENT IA LOCAL' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkCyan
        Write-Host "Bibliotheque : $LibraryRoot"
        Write-Host "Budget        : $MaxLibrarySizeGB Go | Mode MCP : $Mode"
        Write-Host "Usage         : $(Get-UsageProfileLabel -Profile $UsageProfile)"
        Write-Host "Projet actif  : $ProjectDirectory"
        Write-Host ''
        Show-EnvironmentSummary
        Write-Host ''
        Write-Host '  1. Definir vos besoins et contraintes'
        Write-Host '  2. Installer ou mettre a jour OpenZIM MCP'
        Write-Host '  3. Voir le plan de telechargement (aucun gros fichier)'
        Write-Host '  4. Telecharger le pack ZIM selectionne'
        Write-Host '  5. Configurer OpenZIM MCP dans un projet VS Code'
        Write-Host '  6. Verifier toute l installation'
        Write-Host '  7. Afficher les archives deja installees'
        Write-Host '  8. Rechercher et telecharger les mises a jour'
        Write-Host '  9. Decouvrir d autres documentations Kiwix'
        Write-Host ' 10. Gerer la mise a jour planifiee (creer, tester, supprimer)'
        Write-Host ' 11. Parcours guide de bout en bout'
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
                '10' { Start-ScheduledTaskManager }
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
# endregion Interface du menu guide

# region Point d entree
Initialize-EffectiveSettings
if ([string]::IsNullOrWhiteSpace($Action)) {
    Start-BeginnerMenu
}
else {
    Invoke-OpenZimAction -RequestedAction $Action
}
# endregion Point d entree
