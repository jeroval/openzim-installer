#requires -Version 5.1
Set-StrictMode -Version Latest
foreach ($module in @('LocalCodex.Common','Hermes','Models')) { Import-Module (Join-Path $PSScriptRoot "$module.psm1") }

function Get-LocalCodexFingerprint {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory)
    $candidate = Read-LocalCodexJson (Join-Path $StateDirectory 'candidate.json')
    $models = (Invoke-LocalCodexOllama $Settings '/api/tags').models
    $model = @($models | Where-Object name -EQ $candidate.model)
    if ($model.Count -ne 1) { throw 'Modele candidat absent ou ambigu.' }
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    $configHash = (Get-FileHash -LiteralPath (Join-Path $paths.Home 'config.yaml')).Hash
    $version = (Invoke-LocalCodexOllama $Settings '/api/version').version
    $git = (Get-Command git.exe -ErrorAction Stop).Source
    $revision = (Invoke-LocalCodexProcess $git @('-C',$paths.Root,'rev-parse','HEAD')).Output.Trim()
    $dirty = (Invoke-LocalCodexProcess $git @('-C',$paths.Root,'status','--porcelain','--untracked-files=no')).Output.Trim()
    if ($revision -ne $candidate.hermesRevision -or $dirty) { throw 'Runtime Hermes different du candidat.' }
    $repository = Split-Path -Parent $PSScriptRoot
    $sourceHashes = foreach ($file in @('scripts\OpenZimCompatServer.py','scripts\Measure-LocalCodex.py','scripts\Test-LocalCodexAcp.py')) {
        (Get-FileHash -LiteralPath (Join-Path $repository $file)).Hash
    }
    "$($model[0].digest)|$($candidate.contextTokens)|$revision|$version|$configHash|$env:COMPUTERNAME|$($sourceHashes -join ':')"
}

function Invoke-LocalCodexBenchmark {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory)
    $candidate = Read-LocalCodexJson (Join-Path $StateDirectory 'candidate.json')
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    $fingerprint = Get-LocalCodexFingerprint $Settings $StateDirectory
    $measurements = @()
    foreach ($context in @($Settings.benchmark.contexts)) {
        if ($context -lt $Settings.hermes.minimumContextTokens) { throw 'Contexte benchmark incompatible avec Hermes.' }
        foreach ($iteration in 1..[int] $Settings.benchmark.repetitions) {
            try {
                $result = Invoke-LocalCodexProcess $paths.Python @(
                    (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Measure-LocalCodex.py'),
                    '--url', $Settings.ollama.baseUrl, '--model', $candidate.model,
                    '--context', [string] $context, '--tokens', [string] $Settings.benchmark.outputTokens,
                    '--timeout', [string] $Settings.ollama.timeoutSeconds
                ) -TimeoutSeconds ([int] $Settings.ollama.timeoutSeconds + 15)
                $measurement = $result.Output | ConvertFrom-Json
            }
            catch { $measurement = [pscustomobject]@{ status = 'FAIL'; contextTokens = $context; error = $_.Exception.Message } }
            $measurements += $measurement
        }
    }
    $report = [pscustomobject]@{
        schemaVersion = 1; fingerprint = $fingerprint; generatedAtUtc = [datetime]::UtcNow.ToString('o')
        status = if (@($measurements | Where-Object status -NE 'PASS').Count -eq 0 -and $measurements.Count -gt 0) { 'PASS' } else { 'FAIL' }
        measurements = $measurements
        note = 'Mesures de la machine entiere ; pics echantillonnes, pas de garantie de demarrage a froid. Aucun changement automatique de profil.'
    }
    Write-LocalCodexJson (Join-Path $StateDirectory 'benchmark.json') $report
    return $report
}

Export-ModuleMember -Function Get-LocalCodexFingerprint,Invoke-LocalCodexBenchmark
