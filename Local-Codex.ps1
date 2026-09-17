#requires -Version 5.1
<#
.SYNOPSIS
Gere Hermes, Qwen/Ollama et la documentation OpenZIM sous Windows.
.DESCRIPTION
Plan et Status ne telechargent rien. Install reutilise les modeles presents ;
un modele absent exige -DownloadModel. La certification conditionne la promotion.
Les anciennes commandes restent disponibles pour la bibliotheque Knowledge.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Menu','Plan','Install','Configure','Benchmark','Certify','Status','Doctor','Update','Rollback','Uninstall','Knowledge')]
    [string] $Action = 'Menu',
    [string] $ConfigPath = (Join-Path $PSScriptRoot 'config\LocalCodex.Settings.json'),
    [string] $StateDirectory = (Join-Path $PSScriptRoot '.local-codex'),
    [string] $ProjectDirectory = $PSScriptRoot,
    [switch] $DownloadModel,
    [switch] $SkipValidation,
    [switch] $Promote
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
foreach ($module in @('LocalCodex.Common','Models','Hermes','OpenZim','Hardware','Doctor','Benchmark','Certification','Updates','OpenZim.Common')) {
    Import-Module (Join-Path $PSScriptRoot "modules\$module.psm1")
}
$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
$settings = Get-LocalCodexConfiguration $ConfigPath
$model = Get-LocalCodexModel $settings

if ($Action -eq 'Menu') {
    do {
        Write-Host "`nLOCAL-CODEX`n1. Installer Local-Codex`n2. Verifier mon installation`n3. Gerer la documentation locale`n4. Mettre a jour (candidat)`n5. Parametres / plan`n6. Desactiver Local-Codex`nA. Options avancees`nQ. Quitter"
        $choice = Read-Host 'Choix'
        $actions = @{ '1'='Install'; '2'='Doctor'; '3'='Knowledge'; '4'='Update'; '5'='Plan'; '6'='Uninstall' }
        if ($choice -eq 'A') {
            Write-Host 'Actions avancees : Configure, Benchmark, Certify, Rollback. Exemple : .\Local-Codex.ps1 -Action Certify'
        }
        elseif ($actions.ContainsKey($choice)) {
            try {
                & $PSCommandPath -Action $actions[$choice] -ConfigPath $ConfigPath -StateDirectory $StateDirectory -ProjectDirectory $ProjectDirectory
            }
            catch { Write-Warning $_.Exception.Message }
        }
    } while ($choice -ne 'Q')
    return
}

if ($Action -eq 'Knowledge') {
    & (Join-Path $PSScriptRoot 'Start-OpenZimAssistant.ps1') -ConfigPath $settings.LegacyConfigPath
    return
}
if ($Action -eq 'Plan') {
    [pscustomobject]@{
        Harness = 'Hermes'; Runtime = 'Ollama'; Model = $model.ollamaTag; Status = $model.status
        ContextCandidate = $settings.model.contextTokens; HermesRevision = $settings.hermes.revision
        ApproximateModelDownloadGB = $model.hardware.approximateDownloadGB
        KnowledgeConfig = $settings.LegacyConfigPath; StateDirectory = $StateDirectory
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
    Get-LocalCodexDoctor $settings $StateDirectory $ProjectDirectory
    return
}

if (-not $PSCmdlet.ShouldProcess($StateDirectory, "Local-Codex : $Action")) { return }
$mutex = Enter-OpenZimMutex -Scope $StateDirectory
try {
    Initialize-OpenZimLog -Directory (Join-Path $PSScriptRoot $settings.logging.directory) -Prefix 'local-codex' -RetentionDays $settings.logging.retentionDays | Out-Null
    Write-OpenZimLog -Level INFO -Event 'action_started' -Message $Action
    if ($Action -in @('Install','Update')) {
        # Les composants partages deja installes ne sont jamais upgrades implicitement.
        if (-not (Get-Command ollama.exe -ErrorAction SilentlyContinue)) {
            & (Join-Path $PSScriptRoot 'scripts\Install-LocalAi.ps1')
        }
        if (-not (Get-Command code.cmd -ErrorAction SilentlyContinue)) { throw 'Installez Visual Studio Code puis relancez Install.' }
        if (-not (Get-Command uv.exe -ErrorAction SilentlyContinue)) {
            & (Join-Path $PSScriptRoot 'scripts\Install-OpenZimMcp.ps1') -Version $settings.openzim.version
        }
        $uvRoot = (Invoke-LocalCodexProcess (Get-Command uv.exe).Source @('tool','dir')).Output.Trim()
        if (-not (Test-Path -LiteralPath (Join-Path $uvRoot 'openzim-mcp\Scripts\python.exe'))) {
            & (Join-Path $PSScriptRoot 'scripts\Install-OpenZimMcp.ps1') -Version $settings.openzim.version
        }
        Install-LocalCodexHermes $settings $StateDirectory | Out-Null
        New-LocalCodexModelProfile $settings $StateDirectory -DownloadModel:$DownloadModel | Out-Null
        $extensions = & (Get-Command code.cmd).Source --list-extensions
        if ($LASTEXITCODE -ne 0) { throw 'Inventaire des extensions VS Code impossible.' }
        if ('formulahendry.acp-client' -notin $extensions) {
            & (Get-Command code.cmd).Source --install-extension formulahendry.acp-client
            if ($LASTEXITCODE -ne 0) { throw 'Installation du client ACP echouee.' }
        }
    }
    if ($Action -in @('Install','Update','Configure')) {
        $candidatePath = Join-Path $StateDirectory 'candidate.json'
        if (-not (Test-Path -LiteralPath $candidatePath)) { New-LocalCodexModelProfile $settings $StateDirectory | Out-Null }
        $candidate = Read-LocalCodexJson $candidatePath
        if ($candidate.hermesRevision -ne $settings.hermes.revision -or $candidate.contextTokens -ne $settings.model.contextTokens -or $candidate.modelId -ne $settings.model.id) {
            throw 'Candidat different de la configuration ; executer Install ou Update.'
        }
        Set-LocalCodexHermesConfiguration $settings $candidate $StateDirectory (Get-LocalCodexOpenZim $settings)
        Set-LocalCodexVSCode $settings $StateDirectory $ProjectDirectory
        Set-LocalCodexCandidateRelease $settings $StateDirectory | Out-Null
        Set-OpenZimProjectInstructions -WorkspacePath $ProjectDirectory | Out-Null
    }
    if ($Action -eq 'Benchmark' -or ($Action -in @('Install','Update') -and -not $SkipValidation)) {
        Invoke-LocalCodexBenchmark $settings $StateDirectory
    }
    if ($Action -eq 'Certify' -or ($Action -in @('Install','Update') -and -not $SkipValidation)) {
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
        Write-Host 'Local-Codex desactive. Les composants, sessions, modeles et archives sont conserves. Voir docs/Local-Codex.md pour le retrait complet.'
    }
    Write-OpenZimLog -Level INFO -Event 'action_completed' -Message $Action
}
catch {
    Write-OpenZimLog -Level ERROR -Event 'action_failed' -Message $_.Exception.Message
    throw
}
finally { Exit-OpenZimMutex $mutex }
