#requires -Version 5.1

Set-StrictMode -Version Latest

foreach ($module in @('LocalCodex.Common', 'Hermes', 'Updates', 'OpenZim.Common')) {
    Import-Module (Join-Path $PSScriptRoot "$module.psm1")
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
    }
}

Export-ModuleMember -Function Initialize-LocalCodexProject,Set-LocalCodexProjectAgentConfiguration,Resolve-LocalCodexProjectRoot
