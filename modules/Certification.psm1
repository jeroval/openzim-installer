#requires -Version 5.1
Set-StrictMode -Version Latest
foreach ($module in @('LocalCodex.Common','Doctor','Benchmark','Hermes')) { Import-Module (Join-Path $PSScriptRoot "$module.psm1") }

function Get-LocalCodexAgentEvidenceLabel {
    param([Parameter(Mandatory)][string] $Name)
    $labels = @{
        acp = 'connexion ACP etablie'; streaming = 'evenements ACP recus'; toolActivity = 'activite des outils visible'
        permissionRequest = 'demande d autorisation recue'; diffPresentation = 'modification de fichier presentee'
        search = 'recherche de fichiers executee'; read = 'lecture de fichiers executee'; plan = 'plan de correction explique'
        diagnosis = 'causes des defauts expliquees'; multiFileEdit = 'deux fichiers corriges'; patch = 'outil de modification utilise'
        terminal = 'commandes de test executees'; observedFailure = 'echec initial observe'; retest = 'tests relances apres correction'
        build = 'verification de syntaxe executee'; testsPreserved = 'tests existants preserves'; openzimCall = 'outil OpenZIM appele'
        documentationRetrieval = 'documentation locale retrouvee'; completed = 'scenario mene a son terme'
        noExternalNetwork = 'aucun outil reseau externe utilise'
    }
    if ($labels.ContainsKey($Name)) { return $labels[$Name] }
    return "preuve $Name"
}

function Invoke-LocalCodexCertification {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory,
        [Parameter(Mandatory)][string] $ProjectDirectory)
    $doctor = Get-LocalCodexDoctor $Settings $StateDirectory $ProjectDirectory
    $checks = @($doctor.checks | Where-Object name -NE 'AgentScenario')
    $fingerprint = $null
    $scenario = $null
    try {
        $fingerprint = Get-LocalCodexFingerprint $Settings $StateDirectory
        $benchmark = Read-LocalCodexJson (Join-Path $StateDirectory 'benchmark.json')
        $candidate = Read-LocalCodexJson (Join-Path $StateDirectory 'candidate.json')
        $measurements = @($benchmark.measurements | Where-Object contextTokens -EQ $candidate.contextTokens)
        if ($benchmark.status -ne 'PASS' -or $benchmark.fingerprint -ne $fingerprint -or
            $measurements.Count -lt $Settings.benchmark.repetitions -or @($measurements | Where-Object status -NE 'PASS').Count -gt 0) {
            throw 'Benchmark absent, echoue ou different du candidat.'
        }
        $checks += [pscustomobject]@{ name = 'Benchmark'; status = 'PASS'; detail = 'Mesures du candidat verifiees' }
    }
    catch { $checks += [pscustomobject]@{ name = 'Benchmark'; status = 'FAIL'; detail = $_.Exception.Message } }
    if (@($checks | Where-Object status -NE 'PASS').Count -eq 0) {
        try {
            $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
            $workspace = Join-Path $StateDirectory ('runs\certify-' + [guid]::NewGuid().ToString('N'))
            $output = Invoke-LocalCodexProcess $paths.Python @(
                (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Test-LocalCodexAcp.py'),
                '--executable', $paths.Executable, '--home', $paths.Home, '--workspace', $workspace,
                '--timeout', [string] $Settings.certification.timeoutSeconds
            ) -TimeoutSeconds ([int] $Settings.certification.timeoutSeconds + 90)
            $scenario = $output.Output | ConvertFrom-Json
            foreach ($property in $scenario.checks.PSObject.Properties) {
                $passed = $property.Value -eq $true
                $label = Get-LocalCodexAgentEvidenceLabel $property.Name
                $detail = if ($passed) {
                    "Valide : $label. Preuves : $workspace"
                }
                else {
                    "Non observe : $label. Consultez session-evidence.json dans $workspace"
                }
                $checks += [pscustomobject]@{ name = 'Agent.' + $property.Name; status = if ($passed) { 'PASS' } else { 'FAIL' }; detail = $detail }
            }
            $scenarioDetail = [string] $scenario.error
            if ([string]::IsNullOrWhiteSpace($scenarioDetail)) {
                $failedEvidence = @($scenario.checks.PSObject.Properties | Where-Object Value -NE $true)
                $testSummary = if ([string] $scenario.finalTests -match 'FAILED \(failures=(\d+)\)') {
                    "$($Matches[1]) test(s) encore en echec"
                } elseif ([string] $scenario.finalTests -match '(?m)^OK\s*$') {
                    'tests finaux reussis'
                } else { 'resultat final des tests non confirme' }
                $scenarioDetail = "$($failedEvidence.Count) preuve(s) manquante(s), $testSummary. Dossier : $workspace"
            }
            $checks += [pscustomobject]@{ name = 'AgentScenario'; status = $scenario.status; detail = $scenarioDetail }
        }
        catch { $checks += [pscustomobject]@{ name = 'AgentScenario'; status = 'FAIL'; detail = $_.Exception.Message } }
    }
    else { $checks += [pscustomobject]@{ name = 'AgentScenario'; status = 'NOT_RUN'; detail = 'Corriger les prerequis avant le scenario.' } }
    $report = [pscustomobject]@{
        schemaVersion = 1; generatedAtUtc = [datetime]::UtcNow.ToString('o'); fingerprint = $fingerprint
        status = if (@($checks | Where-Object status -NE 'PASS').Count -eq 0) { 'PASS' } else { 'FAIL' }
        checks = $checks; scenario = $scenario
    }
    Write-LocalCodexJson (Join-Path $StateDirectory 'certification.json') $report
    return $report
}

Export-ModuleMember -Function Invoke-LocalCodexCertification,Get-LocalCodexAgentEvidenceLabel
