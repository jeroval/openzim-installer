#requires -Version 5.1
Set-StrictMode -Version Latest
foreach ($module in @('LocalCodex.Common','Hermes','Benchmark')) { Import-Module (Join-Path $PSScriptRoot "$module.psm1") }

function Get-LocalCodexReleases {
    param([Parameter(Mandatory)][string] $StateDirectory)
    $path = Join-Path $StateDirectory 'releases.json'
    if (Test-Path -LiteralPath $path) { return Read-LocalCodexJson $path }
    [pscustomobject]@{ schemaVersion = 1; active = $null; stable = $null; previous = $null; candidate = $null }
}

function Set-LocalCodexCandidateRelease {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory)
    $releases = Get-LocalCodexReleases $StateDirectory
    $candidate = Read-LocalCodexJson (Join-Path $StateDirectory 'candidate.json')
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    $releases.candidate = [pscustomobject]@{
        status = 'candidate'; model = $candidate.model; contextTokens = $candidate.contextTokens
        revision = $Settings.hermes.revision; home = $paths.Home; executable = $paths.Executable
        configHash = (Get-FileHash -LiteralPath (Join-Path $paths.Home 'config.yaml')).Hash
    }
    # Premiere installation utilisable en candidat ; un stable existant reste actif.
    if ($null -eq $releases.active) { $releases.active = $releases.candidate }
    Write-LocalCodexJson (Join-Path $StateDirectory 'releases.json') $releases
    return $releases
}

function Publish-LocalCodexCandidate {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory)
    $report = Read-LocalCodexJson (Join-Path $StateDirectory 'certification.json')
    $fingerprint = Get-LocalCodexFingerprint $Settings $StateDirectory
    $required = @('Git','VSCode','ACPClient','Hermes','ACP','Ollama','Qwen','Configuration',
        'OpenZimMCP','ZimLibrary','Benchmark','AgentScenario','Agent.acp','Agent.streaming',
        'Agent.toolActivity','Agent.permissionRequest','Agent.diffPresentation','Agent.search',
        'Agent.read','Agent.plan','Agent.diagnosis','Agent.multiFileEdit','Agent.patch',
        'Agent.terminal','Agent.observedFailure','Agent.retest','Agent.build',
        'Agent.testsPreserved','Agent.openzimCall','Agent.documentationRetrieval',
        'Agent.completed','Agent.noNetworkOrDelegation')
    foreach ($name in $required) {
        $matches = @($report.checks | Where-Object name -EQ $name)
        if ($matches.Count -ne 1 -or $matches[0].status -ne 'PASS') {
            throw "Promotion refusee : verification obligatoire absente ou echouee ($name)."
        }
    }
    if ($report.status -ne 'PASS' -or $report.fingerprint -ne $fingerprint -or
        @($report.checks | Where-Object status -NE 'PASS').Count -gt 0 -or $report.checks.Count -eq 0) {
        throw 'Promotion refusee : certification absente, echouee ou perimee.'
    }
    $releases = Get-LocalCodexReleases $StateDirectory
    if ($null -eq $releases.candidate) { throw 'Aucun candidat configure.' }
    $candidate = Read-LocalCodexJson (Join-Path $StateDirectory 'candidate.json')
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    if ($releases.candidate.model -ne $candidate.model -or
        $releases.candidate.home -ne $paths.Home -or
        $releases.candidate.revision -ne $candidate.hermesRevision -or
        $releases.candidate.contextTokens -ne $candidate.contextTokens -or
        $releases.candidate.configHash -ne (Get-FileHash -LiteralPath (Join-Path $paths.Home 'config.yaml')).Hash) {
        throw 'Candidat configure different du candidat certifie ; relancer Configure.'
    }
    if ($null -ne $releases.stable -and $releases.stable.home -eq $releases.candidate.home) { return $releases }
    $releases.previous = $releases.stable
    $releases.stable = $releases.candidate
    $releases.stable.status = 'certified'
    $releases.active = $releases.stable
    Write-LocalCodexJson (Join-Path $StateDirectory 'releases.json') $releases
    return $releases
}

function Restore-LocalCodexRelease {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string] $StateDirectory)
    $releases = Get-LocalCodexReleases $StateDirectory
    if ($null -eq $releases.previous) { throw 'Aucune version stable precedente a restaurer.' }
    $previous = $releases.previous
    if (-not (Test-Path -LiteralPath $previous.executable -PathType Leaf) -or
        (Get-FileHash -LiteralPath (Join-Path $previous.home 'config.yaml')).Hash -ne $previous.configHash) {
        throw 'Version precedente absente ou modifiee ; rollback interrompu.'
    }
    if ($PSCmdlet.ShouldProcess($previous.home, 'Restaurer le profil stable precedent sans retéléchargement')) {
        $releases.previous = $releases.stable
        $releases.stable = $previous
        $releases.active = $previous
        Write-LocalCodexJson (Join-Path $StateDirectory 'releases.json') $releases
    }
    return $releases
}

Export-ModuleMember -Function Get-LocalCodexReleases,Set-LocalCodexCandidateRelease,Publish-LocalCodexCandidate,Restore-LocalCodexRelease
