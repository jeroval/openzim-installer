#requires -Version 5.1

Set-StrictMode -Version Latest

foreach ($module in @('LocalCodex.Common', 'Hermes', 'Updates', 'OpenZim', 'OpenZim.Common')) {
    Import-Module (Join-Path $PSScriptRoot "$module.psm1")
}

function Set-LocalCodexNativeMcp {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ProjectDirectory,
        [Parameter(Mandatory)] $McpServer
    )

    if ([string]::IsNullOrWhiteSpace([string] $McpServer.command) -or @($McpServer.args).Count -eq 0) {
        throw 'Configuration OpenZIM native incomplete.'
    }
    $project = Resolve-LocalCodexProjectRoot $ProjectDirectory
    $configurationPath = Join-Path $project '.vscode\mcp.json'
    $managedPath = Join-Path $project '.local-codex\native-mcp-managed.json'
    $configuration = if (Test-Path -LiteralPath $configurationPath -PathType Leaf) {
        Read-LocalCodexJson $configurationPath
    } else {
        [pscustomobject]@{ servers = [pscustomobject]@{} }
    }
    if ($null -eq $configuration.PSObject.Properties['servers']) {
        $configuration | Add-Member NoteProperty servers ([pscustomobject]@{})
    }
    $desired = [pscustomobject]@{
        type = 'stdio'
        command = [string] $McpServer.command
        args = @($McpServer.args)
    }
    $desiredJson = $desired | ConvertTo-Json -Depth 20 -Compress
    $current = $configuration.servers.PSObject.Properties['openzim']
    if ($null -ne $current) {
        $currentJson = $current.Value | ConvertTo-Json -Depth 20 -Compress
        if ($currentJson -ne $desiredJson) {
            if (-not (Test-Path -LiteralPath $managedPath -PathType Leaf)) {
                throw 'Serveur OpenZIM natif deja configure differemment ; configuration utilisateur preservee.'
            }
            $managed = Read-LocalCodexJson $managedPath
            $managedJson = $managed.server | ConvertTo-Json -Depth 20 -Compress
            if ($currentJson -ne $managedJson) {
                throw 'Serveur OpenZIM natif modifie hors Local-Codex ; configuration utilisateur preservee.'
            }
        }
    }
    $configuration.servers | Add-Member NoteProperty openzim $desired -Force
    if ($PSCmdlet.ShouldProcess($configurationPath, 'Connecter le chat natif VS Code a OpenZIM')) {
        Write-LocalCodexJson $configurationPath $configuration
        Write-LocalCodexJson $managedPath @{ schemaVersion = 1; server = $desired }
        Write-Host "OpenZIM configure pour le chat natif VS Code : $configurationPath" -ForegroundColor Green
    }
}

function Resolve-LocalCodexProjectRoot {
    param([Parameter(Mandatory)][string] $ProjectDirectory)
    $project = (Resolve-Path -LiteralPath $ProjectDirectory -ErrorAction Stop).Path
    if ((Split-Path -Leaf $project) -ieq '.vscode') {
        return Split-Path -Parent $project
    }
    return $project
}

function Set-LocalCodexProjectAgentConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] [string] $StateDirectory,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $ProjectDirectory
    )

    if ([string]::IsNullOrWhiteSpace($ProjectDirectory)) {
        throw 'La configuration du projet requiert un dossier explicite.'
    }
    $project = Resolve-LocalCodexProjectRoot $ProjectDirectory
    Set-LocalCodexVSCode $Settings $StateDirectory $project -WhatIf:$WhatIfPreference
    Set-LocalCodexNativeMcp $project (Get-LocalCodexOpenZim $Settings) -WhatIf:$WhatIfPreference
    Set-OpenZimProjectInstructions -WorkspacePath $project -WhatIf:$WhatIfPreference | Out-Null
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $healthTemplate = Join-Path $repositoryRoot 'templates\Test-LocalCodexHealth.ps1'
    if (-not (Test-Path -LiteralPath $healthTemplate -PathType Leaf)) {
        throw "Script de diagnostic Local-Codex introuvable : $healthTemplate"
    }
    $healthScript = Join-Path $project '.local-codex\Test-LocalCodexHealth.ps1'
    if ($PSCmdlet.ShouldProcess($healthScript, 'Installer le diagnostic local en lecture seule')) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $healthScript)) | Out-Null
        [IO.File]::WriteAllText(
            $healthScript,
            [IO.File]::ReadAllText($healthTemplate),
            [Text.UTF8Encoding]::new($true)
        )
        Write-Host "Commande /verifier-codex preparee : $healthScript" -ForegroundColor Green
    }
    return $project
}

function Initialize-LocalCodexProject {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] [string] $StateDirectory,
        [Parameter(Mandatory)] [string] $ProjectDirectory,
        [switch] $InitializeGit
    )

    $project = [IO.Path]::GetFullPath($ProjectDirectory)
    if (-not (Test-Path -LiteralPath $project -PathType Container)) {
        throw "Dossier projet introuvable : $project"
    }

    $releases = Get-LocalCodexReleases $StateDirectory
    if ($null -eq $releases.active) {
        throw 'Local-Codex n est pas encore installe et configure. Utilisez d abord l option 1.'
    }
    if (-not (Test-Path -LiteralPath $releases.active.executable -PathType Leaf)) {
        throw 'Le runtime Hermes actif est introuvable. Utilisez l option 3 pour diagnostiquer puis relancez l installation.'
    }

    if ($InitializeGit -and -not (Test-Path -LiteralPath (Join-Path $project '.git'))) {
        $git = (Get-Command git.exe -ErrorAction Stop).Source
        if ($PSCmdlet.ShouldProcess($project, 'Initialiser un depot Git local')) {
            Invoke-LocalCodexProcess $git @('init', $project) | Out-Null
        }
    }

    $project = Set-LocalCodexProjectAgentConfiguration $Settings $StateDirectory $project `
        -WhatIf:$WhatIfPreference

    $metadataPath = Join-Path $project '.local-codex\project.json'
    $metadata = [ordered]@{
        schemaVersion = 1
        configuredAtUtc = [datetime]::UtcNow.ToString('o')
        stateDirectory = $StateDirectory
        agent = 'Local-Codex'
        model = $releases.active.model
        healthCheckScript = '.local-codex\Test-LocalCodexHealth.ps1'
    }
    if ($PSCmdlet.ShouldProcess($metadataPath, 'Ecrire la configuration locale du projet')) {
        Write-LocalCodexJson $metadataPath $metadata
    }

    return [pscustomobject]@{
        ProjectDirectory = $project
        GitRepository = Test-Path -LiteralPath (Join-Path $project '.git')
        VSCodeSettings = Join-Path $project '.vscode\settings.json'
        ProjectConfiguration = $metadataPath
        HealthCheck = Join-Path $project '.local-codex\Test-LocalCodexHealth.ps1'
        Prompt = Join-Path $project '.github\prompts\verifier-codex.prompt.md'
        NativeAgent = Join-Path $project '.github\agents\local-codex-native.agent.md'
        NativeMcp = Join-Path $project '.vscode\mcp.json'
    }
}

Export-ModuleMember -Function Initialize-LocalCodexProject,Set-LocalCodexProjectAgentConfiguration,Set-LocalCodexNativeMcp,Resolve-LocalCodexProjectRoot
