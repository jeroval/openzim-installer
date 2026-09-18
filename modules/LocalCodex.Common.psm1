#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'OpenZim.Common.psm1')
$script:LocalCodexMinimumAgentContextTokens = 64000

function Assert-LocalCodexAgentContext {
    param(
        [Parameter(Mandatory)][long] $ContextTokens,
        [long] $ConfiguredMinimum = 64000
    )
    $minimum = [Math]::Max($script:LocalCodexMinimumAgentContextTokens, $ConfiguredMinimum)
    if ($ContextTokens -lt $minimum) {
        throw "Contexte agentique invalide : Hermes exige au moins $minimum tokens. Local-Codex ne reduit jamais cette valeur pour economiser la VRAM."
    }
}

function Read-LocalCodexJson {
    param([Parameter(Mandatory)][string] $Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Write-LocalCodexJson {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)] $Value)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = "$fullPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 40
        [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
        Read-LocalCodexJson $temporary | Out-Null
        if ([IO.File]::Exists($fullPath)) { [IO.File]::Replace($temporary, $fullPath, "$fullPath.previous") }
        else { [IO.File]::Move($temporary, $fullPath) }
    }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Get-LocalCodexConfiguration {
    param([Parameter(Mandatory)][string] $Path)
    $settings = Read-LocalCodexJson $Path
    if ($settings.schemaVersion -ne 1) { throw 'Version de configuration Local-Codex non supportee.' }
    if ($settings.model.id -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Identifiant de modele invalide.' }
    if ($settings.integration.protocol -ne 'ACP' -or
        [string]::IsNullOrWhiteSpace([string] $settings.integration.vscodeExtension) -or
        [string]::IsNullOrWhiteSpace([string] $settings.integration.agentName)) {
        throw 'Integration invalide : ACP, son extension VS Code et le nom de l agent sont obligatoires.'
    }
    if ($null -eq $settings.integration.PSObject.Properties['nativeModelExtension']) {
        $settings.integration | Add-Member NoteProperty nativeModelExtension 'ollama.ollama'
    }
    if ($null -eq $settings.integration.PSObject.Properties['nativeAgentName']) {
        $settings.integration | Add-Member NoteProperty nativeAgentName 'Local-Codex Native'
    }
    if ([string]::IsNullOrWhiteSpace([string] $settings.integration.nativeModelExtension) -or
        [string]::IsNullOrWhiteSpace([string] $settings.integration.nativeAgentName)) {
        throw 'Integration du chat natif VS Code incomplete.'
    }
    # Migration additive du schema 1 : les anciennes configurations restent
    # valides tout en beneficiant de la politique de reprise sure par defaut.
    if ($null -eq $settings.hermes.PSObject.Properties['apiMaxRetries']) {
        $settings.hermes | Add-Member NoteProperty apiMaxRetries 5
    }
    if ($null -eq $settings.hermes.PSObject.Properties['emptyResponseGuard']) {
        $settings.hermes | Add-Member NoteProperty emptyResponseGuard $true
    }
    foreach ($limit in @(
        @($settings.model.contextTokens, 64000, 4194304),
        @($settings.benchmark.repetitions, 1, 20),
        @($settings.benchmark.outputTokens, 1, 8192),
        @($settings.ollama.timeoutSeconds, 10, 3600),
        @($settings.hermes.apiMaxRetries, 1, 10),
        @($settings.certification.timeoutSeconds, 30, 3600)
    )) {
        if ($limit[0] -isnot [int] -and $limit[0] -isnot [long]) { throw 'Parametre numerique entier requis.' }
        if ($limit[0] -lt $limit[1] -or $limit[0] -gt $limit[2]) { throw 'Parametre numerique hors limites.' }
    }
    if (@($settings.benchmark.contexts).Count -eq 0) { throw 'Au moins un contexte benchmark est requis.' }
    foreach ($context in $settings.benchmark.contexts) {
        if (($context -isnot [int] -and $context -isnot [long]) -or
            $context -lt $settings.hermes.minimumContextTokens -or $context -gt 4194304) {
            throw 'Contexte benchmark invalide.'
        }
    }
    $endpoint = [uri] $settings.ollama.baseUrl
    if (-not $endpoint.IsLoopback -or $endpoint.Scheme -notin @('http','https') -or $endpoint.UserInfo) {
        throw 'Ollama doit utiliser une URL locale sans identifiants.'
    }
    Assert-LocalCodexAgentContext $settings.hermes.minimumContextTokens
    Assert-LocalCodexAgentContext $settings.model.contextTokens $settings.hermes.minimumContextTokens
    if ($settings.hermes.revision -notmatch '^[a-f0-9]{40}$') { throw 'Hermes exige une revision Git complete et epinglee.' }
    if ($settings.hermes.emptyResponseGuard -isnot [bool]) { throw 'Le garde-fou de reponse vide Hermes doit etre un booleen.' }
    if ($settings.updates.automaticPromotion) { throw 'La promotion automatique est interdite.' }
    $configDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    $knowledgePath = [Environment]::ExpandEnvironmentVariables($settings.knowledge.config)
    if (-not [IO.Path]::IsPathRooted($knowledgePath)) { $knowledgePath = Join-Path $configDirectory $knowledgePath }
    $knowledge = Read-LocalCodexJson $knowledgePath
    $settings | Add-Member NoteProperty KnowledgeSettings $knowledge
    $settings | Add-Member NoteProperty KnowledgeConfigPath $knowledgePath
    $catalogPath = Join-Path $configDirectory $settings.model.catalog
    $settings | Add-Member NoteProperty CatalogPath $catalogPath
    return $settings
}

function Invoke-LocalCodexProcess {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [string[]] $Arguments = @(),
        [ValidateRange(1,7200)][int] $TimeoutSeconds = 60,
        [hashtable] $Environment = @{},
        [string] $WorkingDirectory = (Get-Location).Path
    )
    # Windows CRT quoting ; aucune interpretation par un shell intermediaire.
    $quoted = foreach ($argument in $Arguments) {
        '"' + ([regex]::Replace([regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath
    $info.Arguments = $quoted -join ' '
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) { $info.EnvironmentVariables[$key] = [string] $Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void] $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw "Delai depasse pour $FilePath ($TimeoutSeconds s)."
        }
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result; Error = $stderr.Result }
        if ($result.ExitCode -ne 0) { throw "$FilePath : code $($result.ExitCode). $($result.Error) $($result.Output)" }
        return $result
    }
    finally { $process.Dispose() }
}

Export-ModuleMember -Function Assert-LocalCodexAgentContext,Read-LocalCodexJson,Write-LocalCodexJson,Get-LocalCodexConfiguration,Invoke-LocalCodexProcess
