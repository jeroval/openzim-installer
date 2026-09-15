#requires -Version 5.1

<#
.SYNOPSIS
Installe Ollama et les modeles locaux choisis lorsqu'ils sont absents.

.DESCRIPTION
Ce script est idempotent : il reutilise Ollama et les modeles deja presents.
Il ne telecharge un modele que si son nom exact est absent de l'API locale
Ollama. Les modeles sont stockes par Ollama et ne comptent pas dans le budget
reserve aux archives ZIM.

.PARAMETER GptOss20B
Installe `gpt-oss:20b` s'il est absent. Telechargement d'environ 14 Go.

.PARAMETER QwenCoder14B
Installe `qwen2.5-coder:14b-instruct-q5_K_M` s'il est absent. Telechargement
d'environ 11 Go.

.EXAMPLE
.\install-local-ai.ps1 -GptOss20B

.EXAMPLE
.\install-local-ai.ps1 -GptOss20B -QwenCoder14B
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch] $GptOss20B,

    [Parameter()]
    [switch] $QwenCoder14B
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Update-SessionPath {
    $pathParts = @(
        ($env:Path -split ';')
        ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';')
        ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';')
    )
    $env:Path = ($pathParts |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique) -join ';'
}

function Get-OllamaExecutable {
    Update-SessionPath
    $command = Get-Command ollama.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    # La commande peut ne pas encore etre visible dans PATH juste apres une
    # installation WinGet. Ces emplacements couvrent les installations Windows
    # par utilisateur et pour toute la machine.
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += Join-Path $env:ProgramFiles 'Ollama\ollama.exe'
    }
    return $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter()] [string[]] $ArgumentList = @()
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "La commande '$FilePath $($ArgumentList -join ' ')' a echoue (code $LASTEXITCODE)."
    }
}

function Get-InstalledOllamaModels {
    param([Parameter(Mandatory)] [string] $OllamaPath)

    try {
        $response = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2
    }
    catch {
        Write-Host 'Demarrage du service local Ollama...' -ForegroundColor DarkCyan
        Start-Process -FilePath $OllamaPath -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
        $response = $null
        foreach ($attempt in 1..40) {
            Start-Sleep -Milliseconds 500
            try {
                $response = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2
                break
            }
            catch {
                # Le service peut prendre quelques secondes au premier demarrage.
            }
        }
        if ($null -eq $response) {
            throw 'Ollama est installe, mais son service local ne repond pas sur 127.0.0.1:11434.'
        }
    }

    return @($response.models | ForEach-Object { [string] $_.name })
}

function Install-OllamaModelIfMissing {
    param(
        [Parameter(Mandatory)] [string] $OllamaPath,
        [Parameter(Mandatory)] [string] $Model,
        [Parameter(Mandatory)] [string] $ApproximateSize,
        [Parameter(Mandatory)] [string[]] $InstalledModels
    )

    if ($Model -in $InstalledModels) {
        Write-Host "Modele deja installe : $Model" -ForegroundColor Green
        return
    }

    $target = "$Model (environ $ApproximateSize)"
    if ($PSCmdlet.ShouldProcess($target, 'Telecharger le modele avec Ollama')) {
        Write-Step "Telechargement de $Model"
        Invoke-NativeCommand -FilePath $OllamaPath -ArgumentList @('pull', $Model)
        Write-Host "Modele installe : $Model" -ForegroundColor Green
    }
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Ce script d installation guidee cible Windows.'
}

Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '       INSTALLATION DU MOTEUR IA LOCAL' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host 'Ollama execute les modeles sur votre ordinateur.'
Write-Host 'Les composants deja installes seront conserves et ignores.'
Write-Host 'Le volume des modeles est distinct du budget des archives ZIM.'
Write-Host ('Selection : GPT-OSS 20B = {0} | Qwen Coder 14B = {1}' -f `
    $(if ($GptOss20B) { 'oui' } else { 'non' }), `
    $(if ($QwenCoder14B) { 'oui' } else { 'non' }))

$ollamaPath = Get-OllamaExecutable
if ([string]::IsNullOrWhiteSpace($ollamaPath)) {
    $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $winget) {
        throw 'Ollama est absent et WinGet est introuvable. Installez App Installer depuis Microsoft Store puis relancez.'
    }

    if ($PSCmdlet.ShouldProcess('Ollama pour Windows', 'Installer avec WinGet')) {
        Write-Step 'Installation de Ollama avec WinGet'
        Invoke-NativeCommand -FilePath $winget.Source -ArgumentList @(
            'install', '--id', 'Ollama.Ollama', '--exact',
            '--accept-source-agreements', '--accept-package-agreements', '--silent'
        )
        $ollamaPath = Get-OllamaExecutable
        if ([string]::IsNullOrWhiteSpace($ollamaPath)) {
            throw "WinGet a termine, mais ollama.exe reste introuvable. Fermez puis relancez l assistant."
        }
    }
}
else {
    Write-Host "Ollama deja installe : $ollamaPath" -ForegroundColor Green
}

if (-not $GptOss20B -and -not $QwenCoder14B) {
    Write-Host 'Aucun modele selectionne. Installation de Ollama terminee.' -ForegroundColor Green
    return
}

if ([string]::IsNullOrWhiteSpace($ollamaPath)) {
    Write-Host 'Mode WhatIf : verification des modeles ignoree tant que Ollama n est pas installe.' -ForegroundColor Yellow
    return
}

Write-Step 'Inventaire des modeles Ollama deja installes'
$installedModels = @(Get-InstalledOllamaModels -OllamaPath $ollamaPath)
if ($installedModels.Count -eq 0) {
    Write-Host 'Aucun modele Ollama detecte.' -ForegroundColor Yellow
}
else {
    Write-Host ("Modeles detectes ({0}) : {1}" -f $installedModels.Count, ($installedModels -join ', '))
}
if ($GptOss20B) {
    Install-OllamaModelIfMissing `
        -OllamaPath $ollamaPath `
        -Model 'gpt-oss:20b' `
        -ApproximateSize '14 Go' `
        -InstalledModels $installedModels
}
if ($QwenCoder14B) {
    Install-OllamaModelIfMissing `
        -OllamaPath $ollamaPath `
        -Model 'qwen2.5-coder:14b-instruct-q5_K_M' `
        -ApproximateSize '11 Go' `
        -InstalledModels $installedModels
}

Write-Host "`nInstallation du moteur IA local terminee." -ForegroundColor Green
Write-Host 'Etape suivante conseillee : installez OpenZIM MCP (option 2), puis preparez les archives (options 3 et 4).'
