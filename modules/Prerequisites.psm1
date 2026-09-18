#requires -Version 5.1

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LocalCodex.Common.psm1')

function Get-LocalCodexPrerequisiteDefinitions {
    @(
        [pscustomobject]@{ Name = 'Git'; Commands = @('git.exe'); PackageId = 'Git.Git' }
        [pscustomobject]@{ Name = 'Visual Studio Code'; Commands = @('code.cmd', 'code.exe'); PackageId = 'Microsoft.VisualStudioCode' }
        [pscustomobject]@{ Name = 'uv'; Commands = @('uv.exe'); PackageId = 'astral-sh.uv' }
        [pscustomobject]@{ Name = 'Ollama'; Commands = @('ollama.exe'); PackageId = 'Ollama.Ollama' }
    )
}

function Find-LocalCodexCommand {
    param([Parameter(Mandatory)][string[]] $Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) { return $command }
    }
    return $null
}

function Update-LocalCodexSessionPath {
    $parts = @(
        $env:Path -split ';'
        [Environment]::GetEnvironmentVariable('Path', 'User') -split ';'
        [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';'
    )
    $env:Path = ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique) -join ';'
}

function Install-LocalCodexWingetPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string[]] $Commands,
        [Parameter(Mandatory)][string] $PackageId
    )

    $existing = Find-LocalCodexCommand $Commands
    if ($null -ne $existing) {
        Write-Host "      [OK] $Name deja disponible" -ForegroundColor Green
        Write-Host "           $($existing.Source)" -ForegroundColor DarkGray
        return $existing.Source
    }

    $winget = Find-LocalCodexCommand @('winget.exe')
    if ($null -eq $winget) {
        throw "$Name est absent et WinGet est introuvable. Installez App Installer puis relancez Local-Codex."
    }
    if (-not $PSCmdlet.ShouldProcess($PackageId, "Installer $Name avec WinGet")) { return $null }

    Write-Host "      [INFO] Installation de $Name avec WinGet" -ForegroundColor Cyan
    Invoke-LocalCodexProcess $winget.Source @(
        'install', '--id', $PackageId, '--exact', '--silent',
        '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity'
    ) -TimeoutSeconds 1800 | Out-Null
    Update-LocalCodexSessionPath

    $installed = Find-LocalCodexCommand $Commands
    if ($null -eq $installed) {
        throw "$Name semble installe, mais sa commande reste introuvable. Fermez puis relancez Local-Codex."
    }
    Write-Host "      [OK] $Name installe : $($installed.Source)" -ForegroundColor Green
    return $installed.Source
}

function Install-LocalCodexPrerequisites {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    foreach ($item in Get-LocalCodexPrerequisiteDefinitions) {
        Install-LocalCodexWingetPackage -Name $item.Name -Commands $item.Commands `
            -PackageId $item.PackageId -WhatIf:$WhatIfPreference | Out-Null
    }
}

function Install-LocalCodexVSCodeExtension {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string] $ExtensionId)

    $code = Find-LocalCodexCommand @('code.cmd', 'code.exe')
    if ($null -eq $code) { throw 'Visual Studio Code est introuvable.' }
    $extensions = @(& $code.Source --list-extensions)
    if ($LASTEXITCODE -ne 0) { throw 'Inventaire des extensions VS Code impossible.' }
    if (@($extensions | Where-Object { $_ -ieq $ExtensionId }).Count -gt 0) {
        Write-Host "      [OK] Extension ACP deja installee : $ExtensionId" -ForegroundColor Green
        return
    }
    if ($PSCmdlet.ShouldProcess($ExtensionId, 'Installer extension ACP dans VS Code')) {
        Write-Host "      [INFO] Installation de l extension ACP : $ExtensionId" -ForegroundColor Cyan
        & $code.Source --install-extension $ExtensionId
        if ($LASTEXITCODE -ne 0) { throw 'Installation du client ACP echouee.' }
        Write-Host "      [OK] Extension ACP installee : $ExtensionId" -ForegroundColor Green
    }
}

Export-ModuleMember -Function Get-LocalCodexPrerequisiteDefinitions,Find-LocalCodexCommand,Install-LocalCodexWingetPackage,Install-LocalCodexPrerequisites,Install-LocalCodexVSCodeExtension
