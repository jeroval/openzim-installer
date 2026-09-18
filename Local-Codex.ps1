#requires -Version 5.1
<#
.SYNOPSIS
Gere Hermes, Qwen/Ollama et la documentation OpenZIM sous Windows.
.DESCRIPTION
Plan et Status ne telechargent rien. Install reutilise les modeles presents ;
un modele absent exige -DownloadModel. La certification conditionne la promotion.
La bibliotheque documentaire reste geree depuis le menu Local-Codex.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Menu','Plan','Install','InitializeProject','Verify','Configure','Benchmark','Certify','Status','Doctor','Update','Rollback','Uninstall','Knowledge','Settings')]
    [string] $Action = 'Menu',
    [string] $ConfigPath,
    [string] $StateDirectory,
    [string] $ProjectDirectory,
    [string] $ModelId,
    [switch] $InitializeGit,
    [switch] $DownloadModel,
    [switch] $SkipValidation,
    [switch] $Promote,
    [switch] $Advanced
)

# Initialiser les chemins par défaut uniquement si non fournis
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config\LocalCodex.Settings.json' }
if (-not $StateDirectory) { $StateDirectory = Join-Path $env:LOCALAPPDATA 'Local-Codex' }

# Normaliser les chemins
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
foreach ($module in @('OpenZim.Common','LocalCodex.Common','Models','Hermes','OpenZim','Hardware','Doctor','Benchmark','Certification','Updates','Project','Knowledge','UserExperience','Prerequisites')) {
    Import-Module (Join-Path $PSScriptRoot "modules\$module.psm1")
}
$settings = Get-LocalCodexConfiguration $ConfigPath
$settings = Import-LocalCodexMachineSelection $settings $StateDirectory
if (-not [string]::IsNullOrWhiteSpace($ModelId)) { $settings.model.id = $ModelId }
$model = Get-LocalCodexModel $settings

if ($Action -eq 'Menu') {
    do {
        Write-Host "`nLOCAL-CODEX`n`n1. Installer Local-Codex`n2. Initialiser un projet`n3. Verifier Local-Codex (bilan de sante detaille)`n4. Gerer la documentation locale`n5. Mettre a jour Local-Codex`n6. Parametres et emplacements`n7. Desinstaller Local-Codex`n`nQ. Quitter"
        $choice = (Read-Host 'Choix').Trim().ToUpperInvariant()
        $directActions = @{ '4'='Knowledge'; '5'='Update'; '6'='Settings'; '7'='Uninstall' }
        if ($choice -eq '1') {
            try {
                $hardware = Get-LocalCodexHardware
                $selection = Get-LocalCodexModelChoices $settings $hardware
                Write-Host "`nMODELES QWEN 3.5 COMPATIBLES" -ForegroundColor Cyan
                $numberToId = @{}
                $index = 0
                foreach ($item in $selection.Choices) {
                    $index++
                    $numberToId[[string] $index] = $item.Id
                    $marker = if ($item.Id -eq $selection.RecommendedId) { ' [RECOMMANDE]' } else { '' }
                    $status = if ($item.Compatible) { 'compatible' } else { 'non conseille' }
                    Write-Host ("{0}. {1} ({2} Go) - {3}: {4}{5}" -f $index, $item.Tag, $item.DownloadGB, $status, $item.Detail, $marker)
                }
                $recommendedNumber = [string] (@($numberToId.Keys | Where-Object { $numberToId[$_] -eq $selection.RecommendedId })[0])
                if ([string]::IsNullOrWhiteSpace($recommendedNumber)) { throw 'Aucun modele compatible avec la RAM detectee.' }
                $selectedNumber = Read-Host "Modele a installer [$recommendedNumber]"
                if ([string]::IsNullOrWhiteSpace($selectedNumber)) { $selectedNumber = $recommendedNumber }
                if (-not $numberToId.ContainsKey($selectedNumber)) { throw 'Choix de modele invalide.' }
                & $PSCommandPath -Action Install -ConfigPath $ConfigPath -StateDirectory $StateDirectory `
                    -ModelId $numberToId[$selectedNumber] -DownloadModel
            }
            catch { Write-Warning $_.Exception.Message }
        }
        elseif ($choice -eq '2') {
            $project = Read-Host 'Dossier du projet a initialiser'
            if ([string]::IsNullOrWhiteSpace($project)) { Write-Warning 'Aucun dossier indique.'; continue }
            $initializeGit = $false
            if ((Test-Path -LiteralPath $project -PathType Container) -and -not (Test-Path -LiteralPath (Join-Path $project '.git'))) {
                $answer = Read-Host 'Ce dossier n est pas un depot Git. L initialiser localement ? [o/N]'
                $initializeGit = $answer -match '^(?i:o|oui|y|yes)$'
            }
            try {
                & $PSCommandPath -Action InitializeProject -ConfigPath $ConfigPath -StateDirectory $StateDirectory -ProjectDirectory $project -InitializeGit:$initializeGit
            }
            catch { Write-Warning $_.Exception.Message }
        }
        elseif ($choice -eq '3') {
            $project = Read-Host 'Racine du projet Local-Codex a verifier (le dossier .vscode est aussi accepte)'
            if ([string]::IsNullOrWhiteSpace($project)) { Write-Warning 'Aucun dossier indique.'; continue }
            try {
                & $PSCommandPath -Action Verify -ConfigPath $ConfigPath `
                    -StateDirectory $StateDirectory -ProjectDirectory $project
            }
            catch { Write-Warning $_.Exception.Message }
        }
        elseif ($directActions.ContainsKey($choice)) {
            try {
                & $PSCommandPath -Action $directActions[$choice] -ConfigPath $ConfigPath `
                    -StateDirectory $StateDirectory -ProjectDirectory $ProjectDirectory
            }
            catch { Write-Warning $_.Exception.Message }
        }
    } while ($choice -ne 'Q')
    return
}

if ($Action -eq 'Knowledge') {
    Start-LocalCodexKnowledge $settings
    return
}
if ($Action -eq 'Settings') {
    $hardware = Get-LocalCodexHardware
    Write-Host "`nPARAMETRES ACTIFS" -ForegroundColor Cyan
    Write-Host ("  Modele           : {0}" -f $model.ollamaTag)
    Write-Host ("  Contexte         : {0} tokens (minimum Hermes : {1})" -f $settings.model.contextTokens, $settings.hermes.minimumContextTokens)
    Write-Host ("  Ollama           : {0}" -f $settings.ollama.baseUrl)
    Write-Host ("  Revision Hermes  : {0}" -f $settings.hermes.revision)
    Write-Host ("  Reprise auto     : {0} tentatives maximum sur erreurs transitoires" -f $settings.hermes.apiMaxRetries)
    Write-Host ("  Chat natif       : {0} + agent {1}" -f $settings.integration.nativeModelExtension, $settings.integration.nativeAgentName)
    Write-Host ("  RAM / VRAM       : {0} Go / {1} Go" -f $hardware.ramTotalGB, $hardware.vramGB)
    Write-Host ("  GPU              : {0}" -f (($hardware.gpu | ForEach-Object Name) -join '; '))
    Show-LocalCodexComponentLocations @(Get-LocalCodexComponentInventory $settings $StateDirectory $ProjectDirectory)
    return
}
if ($Action -eq 'InitializeProject') {
    if ([string]::IsNullOrWhiteSpace($ProjectDirectory)) { throw 'Indiquez -ProjectDirectory ou utilisez l option 2.' }
    Initialize-LocalCodexProject $settings $StateDirectory $ProjectDirectory -InitializeGit:$InitializeGit
    return
}
if ($Action -eq 'Plan') {
    [pscustomobject]@{
        Harness = 'Hermes'; Runtime = 'Ollama'; Model = $model.ollamaTag; Status = $model.status
        ContextCandidate = $settings.model.contextTokens; HermesRevision = $settings.hermes.revision
        ApproximateModelDownloadGB = $model.hardware.approximateDownloadGB
        KnowledgeConfig = $settings.KnowledgeConfigPath; StateDirectory = $StateDirectory
        Hardware = Get-LocalCodexHardware
        Next = 'Install puis Benchmark et Certify ; aucun modele ni ZIM telecharge par Plan.'
    }
    return
}
if ($Action -eq 'Status') {
    Get-LocalCodexReleases $StateDirectory
    return
}
if ($Action -eq 'Doctor') {
    if ([string]::IsNullOrWhiteSpace($ProjectDirectory)) { throw 'Doctor requiert -ProjectDirectory.' }
    $ProjectDirectory = Resolve-LocalCodexProjectRoot $ProjectDirectory
    $report = Get-LocalCodexDoctor $settings $StateDirectory $ProjectDirectory
    Show-LocalCodexVerification $report -Advanced:$Advanced | Out-Null
    return
}
if ($Action -eq 'Verify') {
    if ([string]::IsNullOrWhiteSpace($ProjectDirectory)) {
        throw 'Verification requiert un projet initialise. Utilisez d abord l option 2 ou -ProjectDirectory.'
    }
    $ProjectDirectory = Resolve-LocalCodexProjectRoot $ProjectDirectory
    Write-Host "`nProjet verifie : $ProjectDirectory" -ForegroundColor DarkGray
    Write-Host 'Le bilan commence par les composants, puis lance le scenario agentique si les prerequis sont valides.' -ForegroundColor DarkGray
    $report = Invoke-LocalCodexCertification $settings $StateDirectory $ProjectDirectory
    Show-LocalCodexVerification $report -Advanced:$Advanced | Out-Null
    return
}

if (-not $PSCmdlet.ShouldProcess($StateDirectory, "Local-Codex : $Action")) { return }
$mutex = Enter-OpenZimMutex -Scope $StateDirectory
try {
    Initialize-OpenZimLog -Directory (Join-Path $PSScriptRoot $settings.logging.directory) -Prefix 'local-codex' -RetentionDays $settings.logging.retentionDays | Out-Null
    Write-OpenZimLog -Level INFO -Event 'action_started' -Message $Action
    if ($Action -in @('Install','Update')) {
        $installationTotalSteps = if ($SkipValidation) { 8 } else { 9 }
        Show-LocalCodexInstallationHeader $StateDirectory $model $settings
        if ($Action -eq 'Install' -and -not [string]::IsNullOrWhiteSpace($ModelId)) {
            Save-LocalCodexMachineSelection $StateDirectory $settings.model.id $settings.model.contextTokens
        }
        Write-LocalCodexInstallationStep 1 $installationTotalSteps 'Prerequis Windows' 'Verification de Git, Visual Studio Code, uv et Ollama. Les outils presents ne sont pas reinstalles.'
        Install-LocalCodexPrerequisites
        Write-LocalCodexInstallationResult 'Prerequis disponibles'

        Write-LocalCodexInstallationStep 2 $installationTotalSteps 'Documentation OpenZIM MCP' 'Installation dans un environnement Python isole gere par uv.'
        & (Join-Path $PSScriptRoot 'scripts\Install-OpenZimMcp.ps1') -Version $settings.openzim.version
        Write-LocalCodexInstallationResult 'Serveur OpenZIM MCP disponible'

        Write-LocalCodexInstallationStep 3 $installationTotalSteps 'Bibliotheque documentaire' 'Creation ou reutilisation du dossier contenant les archives .zim.'
        $libraryRoot = [Environment]::ExpandEnvironmentVariables($settings.KnowledgeSettings.libraryRoot)
        [IO.Directory]::CreateDirectory($libraryRoot) | Out-Null
        Write-LocalCodexInstallationResult "Bibliotheque prete : $libraryRoot"

        Write-LocalCodexInstallationStep 4 $installationTotalSteps 'Hermes Agent' 'Hermes fournit les fonctions agentiques : fichiers, terminal, Git, tests, diffs et MCP.'
        Install-LocalCodexHermes $settings $StateDirectory | Out-Null
        Write-LocalCodexInstallationResult 'Hermes et sa passerelle ACP sont valides'

        Write-LocalCodexInstallationStep 5 $installationTotalSteps 'Modele IA Ollama' 'Verification du modele selectionne et creation d un profil Local-Codex avec au moins 64K de contexte.'
        New-LocalCodexModelProfile $settings $StateDirectory -DownloadModel:$DownloadModel | Out-Null
        Write-LocalCodexInstallationResult "Modele pret : $($model.ollamaTag)"

        Write-LocalCodexInstallationStep 6 $installationTotalSteps 'Integration Visual Studio Code' 'Installation du client ACP/Hermes et du fournisseur Ollama pour le chat natif.'
        Install-LocalCodexVSCodeExtension ([string] $settings.integration.vscodeExtension) 'Extension ACP Client'
        Install-LocalCodexVSCodeExtension ([string] $settings.integration.nativeModelExtension) 'Extension Ollama pour le chat natif'
        Write-LocalCodexInstallationResult 'ACP Client et fournisseur Ollama natif disponibles'
    }
    if ($Action -in @('Install','Update','Configure')) {
        if ($Action -in @('Install','Update')) {
            Write-LocalCodexInstallationStep 7 $installationTotalSteps 'Configuration de Hermes' 'Connexion a Ollama/OpenZIM et activation des reprises automatiques sur erreurs transitoires.'
        }
        $candidatePath = Join-Path $StateDirectory 'candidate.json'
        if (-not (Test-Path -LiteralPath $candidatePath)) { New-LocalCodexModelProfile $settings $StateDirectory | Out-Null }
        $candidate = Read-LocalCodexJson $candidatePath
        if ($candidate.hermesRevision -ne $settings.hermes.revision -or $candidate.contextTokens -ne $settings.model.contextTokens -or $candidate.modelId -ne $settings.model.id) {
            throw 'Candidat different de la configuration ; executer Install ou Update.'
        }
        Set-LocalCodexHermesConfiguration $settings $candidate $StateDirectory (Get-LocalCodexOpenZim $settings)
        if (-not [string]::IsNullOrWhiteSpace($ProjectDirectory)) {
            Set-LocalCodexProjectAgentConfiguration $settings $StateDirectory $ProjectDirectory
        }
        if ($Action -in @('Install','Update')) {
            Write-LocalCodexInstallationResult 'Profil Hermes configure pour Ollama et OpenZIM'
            Write-LocalCodexInstallationStep 8 $installationTotalSteps 'Activation du candidat' 'Enregistrement du profil utilisable sans supprimer une version stable precedente.'
        }
        Set-LocalCodexCandidateRelease $settings $StateDirectory | Out-Null
        if ($Action -in @('Install','Update')) {
            Write-LocalCodexInstallationResult 'Profil Local-Codex actif enregistre'
        }
    }
    if ($Action -eq 'Benchmark' -or ($Action -in @('Install','Update') -and -not $SkipValidation)) {
        if ($Action -in @('Install','Update')) {
            Write-LocalCodexInstallationStep 9 $installationTotalSteps 'Test local du modele' 'Trois requetes mesurent la reponse, le debit et la consommation. Comptez quelques secondes a quelques minutes.'
        }
        $benchmarkReport = Invoke-LocalCodexBenchmark $settings $StateDirectory
        Show-LocalCodexBenchmarkSummary $benchmarkReport
    }
    if ($Action -eq 'Certify' -or ($Action -in @('Install','Update') -and
        -not $SkipValidation -and -not [string]::IsNullOrWhiteSpace($ProjectDirectory))) {
        $report = Invoke-LocalCodexCertification $settings $StateDirectory $ProjectDirectory
        $report
        if ($report.status -ne 'PASS') { throw 'Certification echouee : consulter .local-codex/certification.json. Aucun profil promu.' }
        if ($Promote) { Publish-LocalCodexCandidate $settings $StateDirectory }
    }
    if ($Action -eq 'Rollback') { Restore-LocalCodexRelease $StateDirectory }
    if ($Action -eq 'Uninstall') {
        $releases = Get-LocalCodexReleases $StateDirectory
        $releases.active = $null
        Write-LocalCodexJson (Join-Path $StateDirectory 'releases.json') $releases
        Write-Host 'Local-Codex desactive. Les composants, sessions, modeles, projets et archives ZIM sont conserves.'
    }
    if ($Action -in @('Install','Update')) {
        Write-Host "`n============================================================" -ForegroundColor DarkCyan
        Write-Host '             INSTALLATION TERMINEE AVEC SUCCES' -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor DarkCyan
        Show-LocalCodexComponentLocations @(Get-LocalCodexComponentInventory $settings $StateDirectory $ProjectDirectory)
        Write-Host "`nProchaine etape : choisissez 2 pour initialiser un projet, puis 3 pour verifier toute la chaine." -ForegroundColor Cyan
    }
    Write-OpenZimLog -Level INFO -Event 'action_completed' -Message $Action
}
catch {
    Write-OpenZimLog -Level ERROR -Event 'action_failed' -Message $_.Exception.Message
    throw
}
finally { Exit-OpenZimMutex $mutex }
