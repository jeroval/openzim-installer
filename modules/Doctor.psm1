#requires -Version 5.1
Set-StrictMode -Version Latest
foreach ($module in @('LocalCodex.Common','Models','Hermes','OpenZim','Hardware')) { Import-Module (Join-Path $PSScriptRoot "$module.psm1") }

function Test-LocalCodexNativeAgentContent {
    param([AllowEmptyString()][string] $Content)

    $toolsLine = [regex]::Match($Content, '(?m)^tools:\s*\[(?<tools>[^\r\n]*)\]\s*$')
    if (-not $toolsLine.Success) { return $false }

    $tools = @($toolsLine.Groups['tools'].Value -split ',' | ForEach-Object {
        ([string] $_).Trim().Trim([char[]]@([char] 39, [char] 34))
    })
    return (
        $Content -match '(?m)^name:\s*Local-Codex Native\s*$' -and
        'execute' -in $tools -and
        'openzim/*' -in $tools -and
        $Content -match 'local-codex-canonical-code-policy' -and
        $Content -match 'local-codex-project-map-policy'
    )
}

function Get-LocalCodexComponentInventory {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory,
        [string] $ProjectDirectory)

    $items = [Collections.Generic.List[object]]::new()
    $add = {
        param($Name, $Purpose, $Location, $Exists)
        $items.Add([pscustomobject]@{
            Name = $Name; Purpose = $Purpose
            Location = if ([string]::IsNullOrWhiteSpace([string] $Location)) { 'introuvable' } else { [string] $Location }
            Status = if ($Exists) { 'OK' } else { 'ABSENT' }
        })
    }
    foreach ($definition in @(
        @('Git', 'Gestion des versions', @('git.exe')),
        @('Visual Studio Code', 'Interface de developpement', @('code.cmd','code.exe')),
        @('uv', 'Gestion des environnements Python isoles', @('uv.exe')),
        @('Ollama', 'Moteur local du modele IA', @('ollama.exe'))
    )) {
        $command = foreach ($name in $definition[2]) {
            Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($?) { break }
        }
        $command = @($command | Where-Object { $null -ne $_ } | Select-Object -First 1)
        & $add $definition[0] $definition[1] $(if ($command.Count) { $command[0].Source } else { $null }) ($command.Count -eq 1)
    }

    $paths = $null
    try { $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory } catch {}
    & $add 'Hermes Agent' 'Agent local et serveur ACP' $(if ($null -ne $paths) { $paths.Executable } else { Join-Path $StateDirectory 'runtimes' }) ($null -ne $paths -and (Test-Path -LiteralPath $paths.Executable -PathType Leaf))
    & $add 'Profil Hermes' 'Configuration Ollama, contexte et OpenZIM de Hermes' $(if ($null -ne $paths) { Join-Path $paths.Home 'config.yaml' } else { Join-Path $StateDirectory 'profiles' }) ($null -ne $paths -and (Test-Path -LiteralPath (Join-Path $paths.Home 'config.yaml') -PathType Leaf))

    $uv = Get-Command uv.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $openZimPython = $null
    if ($null -ne $uv) {
        try {
            $toolRoot = (Invoke-LocalCodexProcess $uv.Source @('tool','dir')).Output.Trim()
            $openZimPython = Join-Path $toolRoot 'openzim-mcp\Scripts\python.exe'
        } catch {}
    }
    & $add 'OpenZIM MCP' 'Serveur de recherche dans les archives ZIM' $openZimPython (-not [string]::IsNullOrWhiteSpace($openZimPython) -and (Test-Path -LiteralPath $openZimPython -PathType Leaf))

    $library = [Environment]::ExpandEnvironmentVariables($Settings.KnowledgeSettings.libraryRoot)
    & $add 'Bibliotheque ZIM' 'Documentation locale hors ligne' $library (Test-Path -LiteralPath $library -PathType Container)
    $modelRoot = if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_MODELS)) { $env:OLLAMA_MODELS } else { Join-Path $env:USERPROFILE '.ollama\models' }
    & $add 'Modeles Ollama' 'Poids du modele Qwen et profils locaux' $modelRoot (Test-Path -LiteralPath $modelRoot -PathType Container)

    $extensionRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
    $extension = @(Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter "$($Settings.integration.vscodeExtension)-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1)
    & $add 'Extension ACP Client' 'Connexion de VS Code a Hermes par ACP' $(if ($extension.Count) { $extension[0].FullName } else { $extensionRoot }) ($extension.Count -eq 1)
    $nativeExtension = @(Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter "$($Settings.integration.nativeModelExtension)-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1)
    & $add 'Extension Ollama VS Code' 'Expose les modeles Ollama dans le chat natif' $(if ($nativeExtension.Count) { $nativeExtension[0].FullName } else { $extensionRoot }) ($nativeExtension.Count -eq 1)
    & $add 'Etat Local-Codex' 'Profils, rapports, selection machine et versions' $StateDirectory (Test-Path -LiteralPath $StateDirectory -PathType Container)
    & $add 'Journaux' 'Historique technique des operations' (Join-Path (Split-Path -Parent $PSScriptRoot) $Settings.logging.directory) (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) $Settings.logging.directory) -PathType Container)
    if (-not [string]::IsNullOrWhiteSpace($ProjectDirectory)) {
        & $add 'Configuration du projet' 'Declaration de l agent ACP pour ce projet' (Join-Path $ProjectDirectory '.vscode\settings.json') (Test-Path -LiteralPath (Join-Path $ProjectDirectory '.vscode\settings.json') -PathType Leaf)
        & $add 'Agent natif VS Code' 'Instructions et outils optimises pour le modele local' (Join-Path $ProjectDirectory '.github\agents\local-codex-native.agent.md') (Test-Path -LiteralPath (Join-Path $ProjectDirectory '.github\agents\local-codex-native.agent.md') -PathType Leaf)
        & $add 'MCP natif VS Code' 'Acces direct du chat natif a OpenZIM' (Join-Path $ProjectDirectory '.vscode\mcp.json') (Test-Path -LiteralPath (Join-Path $ProjectDirectory '.vscode\mcp.json') -PathType Leaf)
    }
    return @($items.ToArray())
}

function Get-LocalCodexDoctor {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory,
        [Parameter(Mandatory)][string] $ProjectDirectory)
    $resolvedProject = (Resolve-Path -LiteralPath $ProjectDirectory -ErrorAction Stop).Path
    if ((Split-Path -Leaf $resolvedProject) -ieq '.vscode') {
        $resolvedProject = Split-Path -Parent $resolvedProject
    }
    $ProjectDirectory = $resolvedProject
    $results = [Collections.Generic.List[object]]::new()
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    $candidatePath = Join-Path $StateDirectory 'candidate.json'
    $checks = [ordered]@{
        Git = { (Invoke-LocalCodexProcess (Get-Command git.exe -ErrorAction Stop).Source @('--version')).Output.Trim() }
        VSCode = {
            $code = Get-Command code.cmd -ErrorAction Stop
            $version = & $code.Source --version
            if ($LASTEXITCODE -ne 0) { throw 'VS Code ne repond pas.' }
            $version -join ' '
        }
        ACPClient = {
            $extensions = & (Get-Command code.cmd -ErrorAction Stop).Source --list-extensions --show-versions
            $extension = [string] $Settings.integration.vscodeExtension
            $client = @($extensions | Where-Object { $_ -like "$extension@*" })
            if ($LASTEXITCODE -ne 0 -or $client.Count -ne 1) { throw "Installer le client ACP VS Code $extension." }
            $client[0]
        }
        OllamaVSCode = {
            $extensions = & (Get-Command code.cmd -ErrorAction Stop).Source --list-extensions --show-versions
            $extension = [string] $Settings.integration.nativeModelExtension
            $provider = @($extensions | Where-Object { $_ -like "$extension@*" })
            if ($LASTEXITCODE -ne 0 -or $provider.Count -ne 1) { throw "Installer le fournisseur Ollama VS Code $extension." }
            $provider[0]
        }
        Hermes = { (Invoke-LocalCodexProcess $paths.Executable @('acp','--version') -Environment @{ HERMES_HOME = $paths.Home }).Output.Trim() }
        ACP = { (Invoke-LocalCodexProcess $paths.Executable @('acp','--check') -Environment @{ HERMES_HOME = $paths.Home }).Output.Trim() }
        Ollama = { (Invoke-LocalCodexOllama $Settings '/api/version').version }
        Qwen = {
            $candidate = Read-LocalCodexJson $candidatePath
            Assert-LocalCodexAgentContext ([long] $candidate.contextTokens) ([long] $Settings.hermes.minimumContextTokens)
            $details = Invoke-LocalCodexOllama $Settings '/api/show' @{ model = $candidate.model }
            if ('tools' -notin @($details.capabilities)) { throw 'Tool calling absent.' }
            if ('thinking' -notin @($details.capabilities)) { throw 'Mode de raisonnement absent.' }
            if ($details.parameters -notmatch "(?m)^num_ctx\s+$($candidate.contextTokens)\s*$") { throw 'Contexte Ollama different du candidat.' }
            "$($candidate.model), contexte $($candidate.contextTokens), outils et raisonnement actifs"
        }
        Configuration = {
            $candidate = Read-LocalCodexJson $candidatePath
            $config = Read-LocalCodexJson (Join-Path $paths.Home 'config.yaml')
            if ($config.model.default -ne $candidate.model -or $config.model.context_length -ne $candidate.contextTokens -or
                $config.model.provider -ne 'custom' -or $config.model.base_url -ne ($Settings.ollama.baseUrl.TrimEnd('/') + '/v1')) { throw 'Configuration Hermes et candidat incoherents.' }
            if ($config.agent.api_max_retries -ne $Settings.hermes.apiMaxRetries -or
                $config.agent.empty_response_guard.enabled -ne $Settings.hermes.emptyResponseGuard) {
                throw 'Politique de reprise automatique Hermes absente ou incoherente.'
            }
            $vscode = Read-LocalCodexJson (Join-Path $ProjectDirectory '.vscode\settings.json')
            $launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Start-LocalCodexAcp.ps1'
            $agentName = [string] $Settings.integration.agentName
            $agent = $vscode.'acp.agents'.PSObject.Properties[$agentName]
            if ($Settings.integration.protocol -ne 'ACP' -or $null -eq $agent -or
                $launcher -notin @($agent.Value.args) -or $StateDirectory -notin @($agent.Value.args)) {
                throw 'Configuration ACP incoherente ou absente ; le mode chatbot seul n est pas accepte.'
            }
            "Hermes / Ollama / ACP coherents, contexte $($candidate.contextTokens), $($config.agent.api_max_retries) tentatives API"
        }
        NativeChat = {
            $candidate = Read-LocalCodexJson $candidatePath
            $nativeAgentPath = Join-Path $ProjectDirectory '.github\agents\local-codex-native.agent.md'
            $nativeAgent = [IO.File]::ReadAllText($nativeAgentPath)
            if (-not (Test-LocalCodexNativeAgentContent $nativeAgent)) {
                throw 'Agent natif Local-Codex absent ou incomplet.'
            }
            $nativeMcp = Read-LocalCodexJson (Join-Path $ProjectDirectory '.vscode\mcp.json')
            $expectedMcp = Get-LocalCodexOpenZim $Settings
            $nativeServer = $nativeMcp.servers.openzim
            if ($null -eq $nativeServer -or $nativeServer.type -ne 'stdio' -or
                $nativeServer.command -ne $expectedMcp.command -or
                (@($nativeServer.args) -join "`n") -ne (@($expectedMcp.args) -join "`n")) {
                throw 'Configuration OpenZIM du chat natif absente ou incoherente.'
            }
            $vscode = Read-LocalCodexJson (Join-Path $ProjectDirectory '.vscode\settings.json')
            if ($vscode.'chat.useAgentsMdFile' -ne $true -or $vscode.'chat.includeApplyingInstructions' -ne $true) {
                throw 'Instructions du projet desactivees pour le chat natif.'
            }
            "$($Settings.integration.nativeAgentName), OpenZIM natif, modele actif $($candidate.model)"
        }
        OpenZimMCP = { (Test-LocalCodexOpenZim $Settings).Output.Trim() }
        ZimLibrary = {
            $library = [Environment]::ExpandEnvironmentVariables($Settings.KnowledgeSettings.libraryRoot)
            $archives = @(Get-ChildItem -LiteralPath $library -Filter '*.zim' -File -Recurse -ErrorAction Stop)
            if ($archives.Count -eq 0) { throw 'Bibliotheque vide.' }
            "$($archives.Count) archives"
        }
    }
    foreach ($name in $checks.Keys) {
        try { $detail = & $checks[$name]; $status = 'PASS' }
        catch { $detail = $_.Exception.Message; $status = 'FAIL' }
        $results.Add([pscustomobject]@{ name = $name; status = $status; detail = [string] $detail })
    }
    $results.Add([pscustomobject]@{ name = 'AgentScenario'; status = 'NOT_RUN'; detail = 'Executer Certify ; Doctor ne prouve pas les capacites agentiques.' })
    [pscustomobject]@{
        generatedAtUtc = [datetime]::UtcNow.ToString('o')
        projectDirectory = $ProjectDirectory
        checks = @($results.ToArray())
        hardware = Get-LocalCodexHardware
        components = @(Get-LocalCodexComponentInventory $Settings $StateDirectory $ProjectDirectory)
    }
}

Export-ModuleMember -Function Get-LocalCodexDoctor,Get-LocalCodexComponentInventory,Test-LocalCodexNativeAgentContent
