#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LocalCodex.Common.psm1')

function Get-LocalCodexHermesPaths {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory)
    $root = Join-Path $StateDirectory "runtimes\hermes-$($Settings.hermes.revision)"
    $profileId = "$($Settings.hermes.revision)-$($Settings.model.id)-$($Settings.model.contextTokens)"
    $candidatePath = Join-Path $StateDirectory 'candidate.json'
    if (Test-Path -LiteralPath $candidatePath) {
        $candidate = Read-LocalCodexJson $candidatePath
        $digest = ([string] $candidate.baseDigest) -replace '^sha256:', ''
        if ($digest -notmatch '^[a-f0-9]{64}$') { throw 'Digest candidat invalide.' }
        $profileId += '-' + $digest.Substring(0,12)
    }
    [pscustomobject]@{
        Root = $root
        Python = Join-Path $root '.venv\Scripts\python.exe'
        Executable = Join-Path $root '.venv\Scripts\hermes.exe'
        Home = Join-Path $StateDirectory "profiles\$profileId"
    }
}

function Install-LocalCodexHermes {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory)
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    $git = (Get-Command git.exe -ErrorAction Stop).Source
    $uv = (Get-Command uv.exe -ErrorAction Stop).Source
    if (-not $PSCmdlet.ShouldProcess($paths.Root, 'Installer Hermes et ACP a la revision epinglee')) { return }
    Write-Host "      Dossier Hermes : $($paths.Root)" -ForegroundColor DarkGray
    Write-Host "      Revision        : $($Settings.hermes.revision)" -ForegroundColor DarkGray
    [IO.Directory]::CreateDirectory($paths.Root) | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $paths.Root '.git'))) {
        Write-Host '      [INFO] Preparation du depot Hermes epingle' -ForegroundColor Cyan
        Invoke-LocalCodexProcess $git @('init', $paths.Root) | Out-Null
        Invoke-LocalCodexProcess $git @('-C', $paths.Root, 'config', 'core.longpaths', 'true') | Out-Null
        Invoke-LocalCodexProcess $git @('-C', $paths.Root, 'remote', 'add', 'origin', 'https://github.com/NousResearch/hermes-agent.git') | Out-Null
    }
    if (-not (Test-Path -LiteralPath (Join-Path $paths.Root 'pyproject.toml'))) {
        Write-Host '      [INFO] Telechargement des sources Hermes' -ForegroundColor Cyan
        Invoke-LocalCodexProcess $git @('-C', $paths.Root, 'fetch', '--depth', '1', 'origin', $Settings.hermes.revision) -TimeoutSeconds 600 | Out-Null
        Invoke-LocalCodexProcess $git @('-C', $paths.Root, 'checkout', '--detach', $Settings.hermes.revision) | Out-Null
    }
    $revision = (Invoke-LocalCodexProcess $git @('-C', $paths.Root, 'rev-parse', 'HEAD')).Output.Trim()
    $dirty = (Invoke-LocalCodexProcess $git @('-C', $paths.Root, 'status', '--porcelain', '--untracked-files=no')).Output.Trim()
    if ($revision -ne $Settings.hermes.revision -or $dirty) { throw 'Checkout Hermes modifie ou revision inattendue ; installation interrompue.' }
    if (Test-Path -LiteralPath $paths.Executable -PathType Leaf) {
        try {
            Invoke-LocalCodexProcess $paths.Python @('-c', 'import acp, mcp') | Out-Null
            Invoke-LocalCodexProcess $paths.Executable @('acp', '--check') -Environment @{ HERMES_HOME = $paths.Home } | Out-Null
            Write-Host "      [OK] Hermes deja installe et valide : $($paths.Executable)" -ForegroundColor Green
            return $paths
        }
        catch { Write-Warning "Installation Hermes incomplete : $($_.Exception.Message)" }
    }
    Write-Host "      [INFO] Creation de l environnement Python Hermes $($Settings.hermes.pythonVersion)" -ForegroundColor Cyan
    Write-Host '             Cette etape peut prendre plusieurs minutes au premier lancement.' -ForegroundColor DarkGray
    Invoke-LocalCodexProcess $uv @('sync', '--frozen', '--no-dev', '--extra', 'acp', '--extra', 'mcp', '--python', $Settings.hermes.pythonVersion) -WorkingDirectory $paths.Root -TimeoutSeconds 1800 | Out-Null
    Invoke-LocalCodexProcess $paths.Executable @('acp', '--check') -Environment @{ HERMES_HOME = $paths.Home } | Out-Null
    Write-Host "      [OK] Hermes installe et ACP valide : $($paths.Executable)" -ForegroundColor Green
    return $paths
}

function New-LocalCodexHermesConfiguration {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)] $Candidate, [Parameter(Mandatory)] $McpServer)
    if (-not $McpServer.command -or @($McpServer.args).Count -eq 0) { throw 'Configuration OpenZIM incomplete.' }
    Assert-LocalCodexAgentContext ([long] $Candidate.contextTokens) ([long] $Settings.hermes.minimumContextTokens)
    # JSON est un sous-ensemble YAML : pas de nouveau parseur ni fusion YAML destructive.
    [ordered]@{
        # Hermes reprend uniquement ses appels modele recuperables. Ce reglage
        # ne rejoue pas le prompt ACP complet ni les outils deja executes.
        agent = [ordered]@{
            api_max_retries = [int] $Settings.hermes.apiMaxRetries
            empty_response_guard = [ordered]@{
                enabled = [bool] $Settings.hermes.emptyResponseGuard
                cost_threshold_usd = 0.25
            }
        }
        model = [ordered]@{
            default = $Candidate.model; provider = 'custom'
            base_url = $Settings.ollama.baseUrl.TrimEnd('/') + '/v1'
            context_length = [int] $Candidate.contextTokens
        }
        mcp_servers = @{ openzim = @{ command = $McpServer.command; args = @($McpServer.args) } }
        # Trois schemas simples : eviter le wrapper tool_call imbrique, moins
        # fiable avec le candidat 9B. Option native verifiee a la revision epinglee.
        tools = @{ tool_search = @{ enabled = 'off' } }
    }
}

function Set-LocalCodexHermesConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)] $Candidate,
        [Parameter(Mandatory)][string] $StateDirectory, [Parameter(Mandatory)] $McpServer)
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    $value = New-LocalCodexHermesConfiguration $Settings $Candidate $McpServer
    $path = Join-Path $paths.Home 'config.yaml'
    $releasePath = Join-Path $StateDirectory 'releases.json'
    if (Test-Path -LiteralPath $releasePath) {
        $releases = Read-LocalCodexJson $releasePath
        if ($null -ne $releases.stable -and $releases.stable.home -eq $paths.Home) {
            $currentConfig = Read-LocalCodexJson $path
            if (($currentConfig | ConvertTo-Json -Depth 30 -Compress) -ne ($value | ConvertTo-Json -Depth 30 -Compress)) {
                throw 'Profil stable immuable : preparez cette configuration dans un autre StateDirectory.'
            }
            return
        }
    }
    if (Test-Path -LiteralPath $path) {
        $existing = [IO.File]::ReadAllText($path)
        $managedPath = Join-Path $paths.Home 'managed-hermes.json'
        if (-not (Test-Path -LiteralPath $managedPath) -or
            (Get-FileHash -LiteralPath $path).Hash -ne (Read-LocalCodexJson $managedPath).sha256) {
            throw 'Configuration Hermes modifiee hors Local-Codex ; fusion manuelle requise pour la preserver.'
        }
    }
    if ($PSCmdlet.ShouldProcess($path, 'Configurer Hermes local avec Ollama et OpenZIM')) {
        if (Test-Path -LiteralPath $path) {
            [IO.File]::WriteAllText((Join-Path $paths.Home 'hermes-config.previous.yaml'), $existing, [Text.UTF8Encoding]::new($false))
        }
        Write-LocalCodexJson $path $value
        Write-LocalCodexJson (Join-Path $paths.Home 'managed-hermes.json') @{ sha256 = (Get-FileHash -LiteralPath $path).Hash }
        $additionalAttempts = [int] $Settings.hermes.apiMaxRetries - 1
        Write-Host ("      [OK] Reprise automatique Hermes : {0} tentatives maximum (1 initiale + {1} reprises)" -f
            $Settings.hermes.apiMaxRetries, $additionalAttempts) -ForegroundColor Green
    }
}

function Set-LocalCodexVSCode {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory,
        [Parameter(Mandatory)][string] $ProjectDirectory)
    $project = (Resolve-Path -LiteralPath $ProjectDirectory -ErrorAction Stop).Path
    $path = Join-Path $project '.vscode\settings.json'
    $value = if (Test-Path -LiteralPath $path) { Read-LocalCodexJson $path } else { [pscustomobject]@{} }
    # Refuse le JSONC non analysable plutot que de perdre commentaires et reglages.
    if ($null -eq $value.PSObject.Properties['acp.agents']) { $value | Add-Member NoteProperty 'acp.agents' ([pscustomobject]@{}) }
    if ($null -eq $value.PSObject.Properties['chat.useAgentsMdFile']) {
        $value | Add-Member NoteProperty 'chat.useAgentsMdFile' $true
    }
    if ($null -eq $value.PSObject.Properties['chat.includeApplyingInstructions']) {
        $value | Add-Member NoteProperty 'chat.includeApplyingInstructions' $true
    }
    $launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Start-LocalCodexAcp.ps1'
    $agent = [pscustomobject]@{
        command = Join-Path $PSHOME 'powershell.exe'
        args = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-StateDirectory',$StateDirectory)
    }
    $agentName = [string] $Settings.integration.agentName
    $current = $value.'acp.agents'.PSObject.Properties[$agentName]
    if ($null -ne $current -and ($current.Value | ConvertTo-Json -Depth 10 -Compress) -ne ($agent | ConvertTo-Json -Depth 10 -Compress)) {
        throw 'Agent ACP Local-Codex deja configure differemment ; configuration preservee.'
    }
    $value.'acp.agents' | Add-Member NoteProperty $agentName $agent -Force
    if ($PSCmdlet.ShouldProcess($path, 'Configurer ACP et les instructions du chat natif VS Code')) { Write-LocalCodexJson $path $value }
}

Export-ModuleMember -Function Get-LocalCodexHermesPaths,Install-LocalCodexHermes,New-LocalCodexHermesConfiguration,Set-LocalCodexHermesConfiguration,Set-LocalCodexVSCode
