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
    $git = Find-HealthCommand @('git.exe')
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

Add-HealthCheck 'OllamaVSCode' {
    $code = Find-HealthCommand @('code.cmd','code.exe')
    $extension = @(& $code.Source --list-extensions --show-versions | Where-Object { $_ -like 'ollama.ollama@*' })
    if ($LASTEXITCODE -ne 0 -or $extension.Count -ne 1) { throw 'Extension officielle ollama.ollama absente.' }
    $extension[0]
}

Add-HealthCheck 'ProjectACP' {
    $settingsPath = Join-Path $projectDirectory '.vscode\settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agentName = [string] $metadata.agent
    if ([string]::IsNullOrWhiteSpace($agentName)) { $agentName = 'Local-Codex' }
    $agent = $settings.'acp.agents'.PSObject.Properties[$agentName]
    if ($null -eq $agent) { throw "Agent ACP '$agentName' absent de .vscode/settings.json." }
    if (-not (Test-Path -LiteralPath ([string] $agent.Value.command) -PathType Leaf)) {
        throw "Commande de lancement ACP absente : $($agent.Value.command)"
    }
    $agentArguments = @($agent.Value.args)
    if ($metadata.stateDirectory -notin $agentArguments -or
        @($agentArguments | Where-Object { $_ -like '*Start-LocalCodexAcp.ps1' }).Count -ne 1) {
        throw 'Arguments ACP incoherents avec ce projet ou son etat Local-Codex.'
    }
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
    $activeConfigPath = Join-Path ([string] $active.home) 'config.yaml'
    if (-not (Test-Path -LiteralPath $activeConfigPath -PathType Leaf)) {
        throw "Configuration du profil actif absente : $activeConfigPath"
    }
    if (-not [string]::IsNullOrWhiteSpace([string] $active.configHash) -and
        (Get-FileHash -LiteralPath $activeConfigPath -Algorithm SHA256).Hash -ne $active.configHash) {
        throw 'La configuration du profil actif a ete modifiee hors de Local-Codex.'
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
    $showBody = @{ model = [string] $active.model } | ConvertTo-Json -Compress
    $details = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/show' -Method Post `
        -ContentType 'application/json' -Body $showBody -TimeoutSec 30 -ErrorAction Stop
    if ('tools' -notin @($details.capabilities)) { throw 'Le modele actif ne declare pas la capacite tools.' }
    if ('thinking' -notin @($details.capabilities)) { throw 'Le modele actif ne declare pas la capacite thinking.' }
    if ([string] $details.parameters -notmatch "(?m)^num_ctx\s+$([long] $active.contextTokens)\s*$") {
        throw "Le contexte charge par Ollama ne correspond pas aux $($active.contextTokens) tokens attendus."
    }
    "$($active.model), contexte $($active.contextTokens), tools disponibles"
}

Add-HealthCheck 'HermesConfiguration' {
    $configPath = Join-Path ([string] $active.home) 'config.yaml'
    $script:hermesConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($hermesConfig.model.default -ne $active.model -or
        [long] $hermesConfig.model.context_length -ne [long] $active.contextTokens -or
        $hermesConfig.model.provider -ne 'custom' -or
        $hermesConfig.model.base_url -ne 'http://127.0.0.1:11434/v1') {
        throw 'Le profil Hermes ne correspond pas au modele Ollama actif.'
    }
    "Modele, fournisseur, URL Ollama et contexte coherents"
}

Add-HealthCheck 'AutomaticRetry' {
    $retryCount = [int] $hermesConfig.agent.api_max_retries
    if ($retryCount -lt 2 -or $retryCount -gt 10) {
        throw "Politique de retry invalide : $retryCount tentative(s)."
    }
    if ($hermesConfig.agent.empty_response_guard.enabled -ne $true) {
        throw 'Le garde-fou Hermes contre les reponses vides est desactive.'
    }
    "$retryCount tentatives maximum, garde-fou de reponse vide actif"
}

Add-HealthCheck 'NativeChat' {
    $settingsPath = Join-Path $projectDirectory '.vscode\settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.'chat.useAgentsMdFile' -ne $true -or $settings.'chat.includeApplyingInstructions' -ne $true) {
        throw 'Chargement des instructions IA du projet desactive dans VS Code.'
    }
    $agentPath = Join-Path $projectDirectory '.github\agents\local-codex-native.agent.md'
    $agentContent = Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8
    if ($agentContent -notmatch '(?m)^name:\s*Local-Codex Native\s*$' -or
        $agentContent -notmatch "openzim/\*" -or $agentContent -notmatch "'execute'" -or
        $agentContent -notmatch '## Dialogue adaptatif et initiative') {
        throw 'Custom agent Local-Codex Native absent ou incomplet.'
    }
    $agentsPath = Join-Path $projectDirectory 'AGENTS.md'
    $agentsContent = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8
    if ($agentsContent -notmatch 'au maximum trois questions' -or
        $agentsContent -notmatch 'demande claire, agis sans question rituelle') {
        throw 'Politique de dialogue adaptatif absente de AGENTS.md.'
    }
    $nativeMcpPath = Join-Path $projectDirectory '.vscode\mcp.json'
    $nativeMcp = Get-Content -LiteralPath $nativeMcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $nativeServer = $nativeMcp.servers.openzim
    $hermesServer = $hermesConfig.mcp_servers.openzim
    if ($null -eq $nativeServer -or $nativeServer.type -ne 'stdio' -or
        $nativeServer.command -ne $hermesServer.command -or
        (@($nativeServer.args) -join "`n") -ne (@($hermesServer.args) -join "`n")) {
        throw 'OpenZIM natif absent ou different de la configuration Hermes.'
    }
    $locations['NativeAgent'] = $agentPath
    $locations['NativeMcp'] = $nativeMcpPath
    'Agent natif, dialogue adaptatif et OpenZIM MCP coherents avec Hermes'
}

Add-HealthCheck 'OpenZimMCP' {
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
            Get-ChildItem -LiteralPath $_ -Filter '*.zim' -File -Recurse -ErrorAction Stop
        }
    } | Select-Object -ExpandProperty FullName -Unique)
    if ($archives.Count -eq 0) { throw 'Aucune archive ZIM accessible.' }
    $emptyArchives = @($archives | Where-Object { (Get-Item -LiteralPath $_).Length -eq 0 })
    if ($emptyArchives.Count -gt 0) { throw "$($emptyArchives.Count) archive(s) ZIM vide(s) detectee(s)." }
    $locations['ZimLibrary'] = @($directories) -join '; '
    $totalBytes = ($archives | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum
    "$($archives.Count) archive(s), $([Math]::Round($totalBytes / 1GB, 2)) Go accessibles"
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
