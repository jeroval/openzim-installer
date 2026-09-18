#requires -Version 5.1

Set-StrictMode -Version Latest

function Test-LocalCodexCheckPattern {
    param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string[]] $Patterns)

    foreach ($pattern in $Patterns) {
        if ($Name -eq $pattern -or ($pattern.EndsWith('.') -and $Name.StartsWith($pattern))) {
            return $true
        }
    }
    return $false
}

function ConvertTo-LocalCodexCheckRow {
    param([Parameter(Mandatory)] $Check, [Parameter(Mandatory)][string] $Group)

    $presentation = switch -Wildcard ([string] $Check.name) {
        'Git' { @('Git', 'Gestion des sources et des projets.', 'Installez Git ou relancez l installation.') }
        'VSCode' { @('Visual Studio Code', 'Editeur qui heberge l agent local.', 'Installez ou relancez Visual Studio Code.') }
        'ACPClient' { @('Extension ACP Client', 'Affiche dans VS Code le chat, les outils, les commandes et les diffs de Hermes.', 'Reinstallez l extension ACP depuis Local-Codex.') }
        'OllamaVSCode' { @('Extension Ollama VS Code', 'Expose le modele local dans le chat natif de VS Code.', 'Reinstallez Local-Codex puis rechargez VS Code.') }
        'Hermes' { @('Hermes Agent', 'Orchestre les fichiers, le terminal, Git, les tests et MCP.', 'Relancez l installation de Local-Codex.') }
        'ACP' { @('Passerelle ACP', 'Relie Hermes a l interface de Visual Studio Code.', 'Reparez Hermes puis reinitialisez le projet.') }
        'Ollama' { @('Ollama', 'Execute le modele de langage sur cette machine.', 'Demarrez Ollama ou relancez son installation.') }
        'Qwen' { @('Modele Qwen', 'Modele local utilise par Hermes avec un contexte minimum de 64K.', 'Reinstallez le modele recommande depuis l option 1.') }
        'Configuration' { @('Configuration du projet', 'Relie ce projet VS Code au profil Hermes actif.', 'Utilisez la racine du projet, puis relancez l option 2.') }
        'NativeChat' { @('Chat natif VS Code', 'Relie le custom agent natif a Ollama et OpenZIM.', 'Relancez l option 2 sur ce projet puis rechargez VS Code.') }
        'Benchmark' { @('Test de performance', 'Verifie que le modele repond avec le profil et le contexte choisis.', 'Relancez l installation ou le benchmark.') }
        'OpenZimMCP' { @('OpenZIM MCP', 'Donne a Hermes un acces local aux archives documentaires ZIM.', 'Reparez OpenZIM MCP depuis le menu Documentation locale.') }
        'ZimLibrary' { @('Bibliotheque ZIM', 'Contient les documentations consultables sans Internet.', 'Telechargez au moins une archive depuis le menu Documentation locale.') }
        'AgentScenario' {
            $action = if ([string] $Check.status -eq 'NOT_RUN') {
                'Lancez l option 3 pour executer la certification complete.'
            } else {
                'Consultez la cause et le dossier de preuves, puis relancez l option 3.'
            }
            @('Scenario agentique complet', 'Prouve le parcours ACP, outils, fichiers, terminal, tests et OpenZIM.', $action)
        }
        'Agent.*' { @(([string] $Check.name -replace '^Agent\.', 'Preuve agent : '), 'Preuve independante produite par le scenario de certification.', 'Consultez le detail puis relancez la verification.') }
        default { @([string] $Check.name, 'Controle technique Local-Codex.', 'Consultez le detail technique.') }
    }
    [pscustomobject]@{
        Group = $Group
        Name = [string] $Check.name
        Label = $presentation[0]
        Purpose = $presentation[1]
        Remediation = $presentation[2]
        State = switch ([string] $Check.status) {
            'PASS' { 'OK' }
            'NOT_RUN' { 'INFO' }
            default { 'ERREUR' }
        }
        Detail = [string] $Check.detail
    }
}

function Get-LocalCodexVerificationView {
    param([Parameter(Mandatory)] $Report)

    $groups = [ordered]@{
        SYSTEM = @('Git', 'VSCode')
        AI = @('Ollama', 'Qwen', 'Hermes', 'ACPClient', 'OllamaVSCode', 'ACP', 'Configuration', 'NativeChat', 'Benchmark')
        AGENT = @('AgentScenario', 'Agent.')
        KNOWLEDGE = @('OpenZimMCP', 'ZimLibrary')
    }
    $rows = @()
    foreach ($check in @($Report.checks)) {
        $group = @($groups.Keys | Where-Object {
            Test-LocalCodexCheckPattern ([string] $check.name) $groups[$_]
        } | Select-Object -First 1)
        if ($group.Count -eq 0) {
            $rows += ConvertTo-LocalCodexCheckRow $check 'AVANCE'
        }
        else {
            $rows += ConvertTo-LocalCodexCheckRow $check $group[0]
        }
    }
    $errors = @($rows | Where-Object State -EQ 'ERREUR')
    $pending = @($rows | Where-Object State -EQ 'INFO')
    [pscustomobject]@{
        Rows = @($rows)
        Ready = $rows.Count -gt 0 -and $errors.Count -eq 0 -and $pending.Count -eq 0
        ErrorCount = $errors.Count
        PendingCount = $pending.Count
    }
}

function Show-LocalCodexVerification {
    param([Parameter(Mandatory)] $Report, [switch] $Advanced)

    $view = Get-LocalCodexVerificationView $Report
    Write-Host "`n============================================================" -ForegroundColor DarkCyan
    Write-Host '              BILAN DE SANTE LOCAL-CODEX' -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host "Chaque controle verifie un maillon reel de la chaine VS Code -> ACP -> Hermes -> Ollama/OpenZIM." -ForegroundColor DarkGray
    foreach ($group in @($view.Rows.Group | Select-Object -Unique)) {
        if ($group -eq 'AVANCE' -and -not $Advanced) { continue }
        Write-Host "`n$group" -ForegroundColor Cyan
        foreach ($row in @($view.Rows | Where-Object Group -EQ $group)) {
            $color = if ($row.State -eq 'OK') { 'Green' } elseif ($row.State -eq 'INFO') { 'Yellow' } else { 'Red' }
            Write-Host ("[{0}] {1}" -f $row.State, $row.Label) -ForegroundColor $color
            Write-Host ("       Role   : {0}" -f $row.Purpose) -ForegroundColor DarkGray
            if (-not [string]::IsNullOrWhiteSpace($row.Detail)) {
                $detailLabel = if ($row.State -eq 'ERREUR') { 'Cause ' } else { 'Detail' }
                Write-Host ("       {0} : {1}" -f $detailLabel, $row.Detail) -ForegroundColor $(if ($row.State -eq 'ERREUR') { 'Red' } else { 'DarkGray' })
            }
            if ($row.State -ne 'OK') {
                Write-Host ("       Action : {0}" -f $row.Remediation) -ForegroundColor Yellow
            }
        }
    }
    if ($null -ne $Report.PSObject.Properties['hardware']) {
        $gpuNames = @($Report.hardware.gpu | ForEach-Object { $_.Name }) -join '; '
        Write-Host "`nMATERIEL DETECTE" -ForegroundColor Cyan
        Write-Host ("  RAM  : {0} Go" -f $Report.hardware.ramTotalGB)
        Write-Host ("  VRAM : {0} Go" -f $Report.hardware.vramGB)
        Write-Host ("  GPU  : {0}" -f $gpuNames)
    }
    if ($null -ne $Report.PSObject.Properties['components']) {
        Show-LocalCodexComponentLocations $Report.components
    }
    if ($view.Ready) {
        Write-Host "`nRESULTAT`nLOCAL-CODEX READY" -ForegroundColor Green
    }
    elseif ($view.ErrorCount -eq 0) {
        Write-Host "`nRESULTAT`nCOMPOSANTS EN BONNE SANTE - CERTIFICATION COMPLETE EN ATTENTE" -ForegroundColor Yellow
        Write-Host 'Aucune erreur technique detectee. Le scenario agentique complet reste a executer.' -ForegroundColor DarkGray
    }
    else {
        Write-Host ("`nRESULTAT`nLOCAL-CODEX NON PRET - {0} erreur(s), {1} verification(s) en attente" -f
            $view.ErrorCount, $view.PendingCount) -ForegroundColor Yellow
        Write-Host 'Les lignes rouges indiquent la cause et l action conseillee.' -ForegroundColor Yellow
    }
    return $view
}

function Write-LocalCodexInstallationStep {
    param(
        [Parameter(Mandatory)][int] $Current,
        [Parameter(Mandatory)][int] $Total,
        [Parameter(Mandatory)][string] $Title,
        [string] $Detail
    )
    Write-Host "`n[$Current/$Total] $Title" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host "      $Detail" -ForegroundColor DarkGray
    }
}

function Write-LocalCodexInstallationResult {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "      [OK] $Message" -ForegroundColor Green
}

function Format-LocalCodexContext {
    param([Parameter(Mandatory)][long] $Tokens)
    if ($Tokens -gt 0 -and $Tokens % 1024 -eq 0) {
        return ('{0}K ({1} tokens)' -f ([long] ($Tokens / 1024)), $Tokens)
    }
    return "$Tokens tokens"
}

function Show-LocalCodexInstallationHeader {
    param([Parameter(Mandatory)][string] $StateDirectory, [Parameter(Mandatory)] $Model,
        [Parameter(Mandatory)] $Settings)
    Write-Host "`n============================================================" -ForegroundColor DarkCyan
    Write-Host '                INSTALLATION LOCAL-CODEX' -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host 'Local-Codex installe et relie les composants suivants :' -ForegroundColor Gray
    Write-Host '  VS Code + ACP  : interface agentique (chat, outils, terminal et diffs)'
    Write-Host '  Hermes         : agent qui planifie et utilise les outils'
    Write-Host '  Ollama + Qwen  : moteur et modele IA executes localement'
    Write-Host '  OpenZIM MCP    : acces aux documentations .zim hors ligne'
    Write-Host "`nDossier Local-Codex : $StateDirectory" -ForegroundColor DarkGray
    Write-Host "Modele selectionne   : $($Model.ollamaTag)" -ForegroundColor DarkGray
    Write-Host ("Contexte configure   : {0}" -f (Format-LocalCodexContext $Settings.model.contextTokens)) -ForegroundColor DarkGray
    Write-Host ("Minimum Hermes       : {0}" -f (Format-LocalCodexContext $Settings.hermes.minimumContextTokens)) -ForegroundColor DarkGray
    Write-Host 'Les composants deja valides seront reutilises.' -ForegroundColor DarkGray
}

function Show-LocalCodexBenchmarkSummary {
    param([Parameter(Mandatory)] $Report)
    $measurements = @($Report.measurements)
    $passed = @($measurements | Where-Object status -EQ 'PASS')
    Write-Host "`nTEST DE PERFORMANCE" -ForegroundColor Cyan
    Write-Host ("  Resultat       : {0}" -f $Report.status) -ForegroundColor $(if ($Report.status -eq 'PASS') { 'Green' } else { 'Red' })
    Write-Host ("  Essais reussis : {0}/{1}" -f $passed.Count, $measurements.Count)
    if ($passed.Count -gt 0) {
        $average = ($passed | Measure-Object -Property tokensPerSecond -Average).Average
        $maximumVram = ($passed | Measure-Object -Property vramPeakMiB -Maximum).Maximum
        Write-Host ("  Debit moyen    : {0:N1} tokens/s" -f $average)
        Write-Host ("  Pic VRAM       : {0:N0} Mio" -f $maximumVram)
    }
    Write-Host '  Rapport        : benchmark.json dans le dossier Local-Codex' -ForegroundColor DarkGray
}

function Show-LocalCodexComponentLocations {
    param([Parameter(Mandatory)][object[]] $Components)
    Write-Host "`nEMPLACEMENTS DES COMPOSANTS" -ForegroundColor Cyan
    foreach ($component in $Components) {
        $color = if ($component.Status -eq 'OK') { 'Green' } else { 'Yellow' }
        Write-Host ("  [{0}] {1}" -f $component.Status, $component.Name) -ForegroundColor $color
        Write-Host ("       Role        : {0}" -f $component.Purpose) -ForegroundColor DarkGray
        Write-Host ("       Emplacement : {0}" -f $component.Location)
    }
}

Export-ModuleMember -Function Get-LocalCodexVerificationView,Show-LocalCodexVerification,Write-LocalCodexInstallationStep,Write-LocalCodexInstallationResult,Format-LocalCodexContext,Show-LocalCodexInstallationHeader,Show-LocalCodexBenchmarkSummary,Show-LocalCodexComponentLocations
