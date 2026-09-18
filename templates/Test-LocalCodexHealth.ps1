#requires -Version 5.1

<#
.SYNOPSIS
Diagnostic local en lecture seule d'un projet initialise par Local-Codex.
#>
[CmdletBinding()]
param([switch] $Json)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$checks = [Collections.Generic.List[object]]::new()
$locations = [ordered]@{}

function Add-HealthCheck {
    param([string] $Name, [scriptblock] $Test)
    try {
        $detail = & $Test
        $script:checks.Add([pscustomobject]@{ name = $Name; status = 'PASS'; detail = [string] $detail })
    }
    catch {
        $script:checks.Add([pscustomobject]@{ name = $Name; status = 'FAIL'; detail = $_.Exception.Message })
    }
}

function Find-HealthCommand {
    param([Parameter(Mandatory)][string[]] $Names)
    foreach ($name in $Names) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return $command }
    }
    throw "Commande introuvable : $($Names -join ', ')"
}

$metadataPath = Join-Path $PSScriptRoot 'project.json'
$metadata = $null
$releases = $null
$active = $null
$hermesConfig = $null

Add-HealthCheck 'ProjectMetadata' {
    $script:metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($metadata.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string] $metadata.stateDirectory)) {
        throw 'Metadonnees Local-Codex invalides.'
    }
    $locations['Project'] = $projectDirectory
    $locations['StateDirectory'] = [string] $metadata.stateDirectory
    $metadataPath
}

Add-HealthCheck 'Git' {
    $git = Get-Command git.exe -CommandType Application -ErrorAction Stop
    (& $git.Source --version | Out-String).Trim()
}

Add-HealthCheck 'VSCode' {
    $code = Find-HealthCommand @('code.cmd','code.exe')
    $versionOutput = @(& $code.Source --version)
    $versionExitCode = $LASTEXITCODE
    if ($versionExitCode -ne 0 -or $versionOutput.Count -eq 0) { throw 'Visual Studio Code ne repond pas.' }
    $locations['VSCode'] = $code.Source
    $versionOutput[0]
}

Add-HealthCheck 'ACPClient' {
    $code = Find-HealthCommand @('code.cmd','code.exe')
    $extension = @(& $code.Source --list-extensions --show-versions | Where-Object { $_ -like 'formulahendry.acp-client@*' })
    if ($LASTEXITCODE -ne 0 -or $extension.Count -ne 1) { throw 'Extension formulahendry.acp-client absente.' }
    $extension[0]
}

Add-HealthCheck 'ProjectACP' {
    $settingsPath = Join-Path $projectDirectory '.vscode\settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agentName = [string] $metadata.agent
    if ([string]::IsNullOrWhiteSpace($agentName)) { $agentName = 'Local-Codex' }
    $agent = $settings.'acp.agents'.PSObject.Properties[$agentName]
    if ($null -eq $agent) { throw "Agent ACP '$agentName' absent de .vscode/settings.json." }
    $locations['ProjectSettings'] = $settingsPath
    $settingsPath
}

Add-HealthCheck 'Release' {
    $releasePath = Join-Path ([string] $metadata.stateDirectory) 'releases.json'
    $script:releases = Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:active = $releases.active
    if ($null -eq $active -or [string]::IsNullOrWhiteSpace([string] $active.executable)) {
        throw 'Aucun profil Local-Codex actif.'
    }
    $locations['Hermes'] = [string] $active.executable
    $locations['HermesProfile'] = [string] $active.home
    $locations['OllamaModels'] = if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_MODELS)) {
        $env:OLLAMA_MODELS
    } else { Join-Path $env:USERPROFILE '.ollama\models' }
    "Profil actif : $($active.model), contexte $($active.contextTokens)"
}

Add-HealthCheck 'HermesACP' {
    if (-not (Test-Path -LiteralPath $active.executable -PathType Leaf)) {
        throw "Executable Hermes absent : $($active.executable)"
    }
    $previousHome = $env:HERMES_HOME
    try {
        $env:HERMES_HOME = [string] $active.home
        $output = (& $active.executable acp --check 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw $output }
        $output
    }
    finally { $env:HERMES_HOME = $previousHome }
}

Add-HealthCheck 'Ollama' {
    $version = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 15 -ErrorAction Stop
    "Version $($version.version)"
}

Add-HealthCheck 'Model' {
    $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 30 -ErrorAction Stop
    if (([string] $active.model) -notin @($tags.models.name)) { throw "Modele actif absent d'Ollama : $($active.model)" }
    if ([long] $active.contextTokens -lt 64000) { throw "Contexte insuffisant : $($active.contextTokens) tokens." }
    "$($active.model), contexte $($active.contextTokens)"
}

Add-HealthCheck 'OpenZimMCP' {
    $configPath = Join-Path ([string] $active.home) 'config.yaml'
    $script:hermesConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $server = $hermesConfig.mcp_servers.openzim
    if ($null -eq $server -or -not (Test-Path -LiteralPath $server.command -PathType Leaf)) {
        throw 'Serveur OpenZIM absent de la configuration Hermes.'
    }
    $arguments = @($server.args)
    if ($arguments.Count -lt 2) { throw 'Aucun dossier ZIM configure dans Hermes.' }
    $selfTestArguments = @($arguments[0], '--self-test') + @($arguments | Select-Object -Skip 1)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = (& $server.command @selfTestArguments 2>&1 | Out-String).Trim()
        $selfTestExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($selfTestExitCode -ne 0 -or $output -notmatch '(?m)^OK') { throw $output }
    $locations['OpenZim'] = [string] $server.command
    ([regex]::Match($output, '(?m)^OK.*$')).Value.Trim()
}

Add-HealthCheck 'ZimLibrary' {
    $directories = @($hermesConfig.mcp_servers.openzim.args | Select-Object -Skip 1)
    $archives = @($directories | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Container) {
            Get-ChildItem -LiteralPath $_ -Filter '*.zim' -File -ErrorAction Stop
        }
    } | Select-Object -ExpandProperty FullName -Unique)
    if ($archives.Count -eq 0) { throw 'Aucune archive ZIM accessible.' }
    $locations['ZimLibrary'] = @($directories) -join '; '
    "$($archives.Count) archive(s) accessible(s)"
}

$failed = @($checks | Where-Object status -EQ 'FAIL')
$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [datetime]::UtcNow.ToString('o')
    status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
    projectDirectory = $projectDirectory
    checks = @($checks.ToArray())
    locations = $locations
    summary = if ($failed.Count -eq 0) { 'Tous les controles machine ont reussi.' } else { "$($failed.Count) controle(s) en echec." }
}

if ($Json) {
    $report | ConvertTo-Json -Depth 10
    return
}

Write-Host "`nBILAN LOCAL-CODEX - $($report.status)" -ForegroundColor $(if ($report.status -eq 'PASS') { 'Green' } else { 'Red' })
foreach ($check in $checks) {
    $color = if ($check.status -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}" -f $check.status, $check.name) -ForegroundColor $color
    Write-Host ("       {0}" -f $check.detail) -ForegroundColor DarkGray
}
