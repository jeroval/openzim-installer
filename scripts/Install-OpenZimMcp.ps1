#requires -Version 5.1

<#
.SYNOPSIS
Installe ou met a jour OpenZIM MCP sous Windows.

.DESCRIPTION
Installe uv avec WinGet si necessaire, installe OpenZIM MCP dans un
environnement isole, verifie la commande et peut creer la configuration MCP
du workspace VS Code.

Le script est concu pour etre relance sans danger : uv est reutilise, OpenZIM
MCP est mis a jour et les autres serveurs presents dans `.vscode/mcp.json`
sont conserves. Avec `-ConfigureVSCode`, un bloc d'instructions documentaires
est aussi cree dans `.github/copilot-instructions.md`.

.PARAMETER ZimDirectory
Dossier racine contenant les archives `.zim`, eventuellement classees dans des
sous-dossiers.

.PARAMETER ConfigureVSCode
Configure automatiquement le projet indique par `ProjectDirectory`.

.PARAMETER Mode
Le mode `simple` expose trois outils courts via une passerelle adaptee aux
modeles locaux compacts. Le mode `advanced` expose directement les
outils complets d'OpenZIM MCP.

.EXAMPLE
.\scripts\Install-OpenZimMcp.ps1

.EXAMPLE
.\scripts\Install-OpenZimMcp.ps1 -ZimDirectory 'D:\Kiwix\ZIM' -ConfigureVSCode

.EXAMPLE
.\scripts\Install-OpenZimMcp.ps1 -ZimDirectory 'D:\Kiwix\ZIM' -ConfigureVSCode -Mode advanced

.EXAMPLE
.\scripts\Install-OpenZimMcp.ps1 -WithReranker -DownloadRerankerModels
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ZimDirectory,

    [Parameter()]
    [switch] $ConfigureVSCode,

    [Parameter()]
    [ValidateSet('simple', 'advanced')]
    [string] $Mode = 'simple',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ProjectDirectory = (Get-Location).Path,

    [Parameter()]
    [switch] $WithReranker,

    [Parameter()]
    [switch] $DownloadRerankerModels,

    [Parameter()]
    [ValidatePattern('^\d+(\.\d+){1,3}([a-zA-Z0-9.-]+)?$')]
    [string] $Version,

    [Parameter()]
    [switch] $ForceMcpConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'modules\OpenZim.Common.psm1') -Force

# region Fonctions utilitaires
function Write-Step {
    param([string] $Message)
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

function Get-ExecutablePath {
    param([Parameter(Mandatory)] [string] $Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }

    return $command.Source
}

function Resolve-ExistingDirectory {
    param([Parameter(Mandatory)] [string] $Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        throw "Le chemin n'est pas un dossier : $Path"
    }

    return $resolved.Path
}

function Set-VSCodeMcpConfiguration {
    param(
        [Parameter(Mandatory)] [string] $WorkspacePath,
        [Parameter(Mandatory)] [string[]] $ArchivePaths,
        [Parameter(Mandatory)] [string] $UvxPath,
        [Parameter(Mandatory)] [string] $OpenZimPythonPath,
        [Parameter(Mandatory)] [string] $CompatibilityServerPath,
        [Parameter(Mandatory)] [ValidateSet('simple', 'advanced')] [string] $ToolMode,
        [Parameter(Mandatory)] [bool] $Overwrite
    )

    $workspace = Resolve-ExistingDirectory -Path $WorkspacePath
    $vscodeDirectory = Join-Path $workspace '.vscode'
    $configurationPath = Join-Path $vscodeDirectory 'mcp.json'

    if (Test-Path -LiteralPath $configurationPath) {
        try {
            $configuration = Get-Content -LiteralPath $configurationPath -Raw -Encoding UTF8 |
                ConvertFrom-Json
        }
        catch {
            throw "Impossible de modifier '$configurationPath' : le fichier n'est pas du JSON valide. Corrigez-le ou sauvegardez-le avant de relancer."
        }
    }
    else {
        $configuration = [pscustomobject]@{
            servers = [pscustomobject]@{}
        }
    }

    if ($null -eq $configuration.PSObject.Properties['servers']) {
        $configuration | Add-Member -MemberType NoteProperty -Name servers -Value ([pscustomobject]@{})
    }

    if ($ToolMode -eq 'simple') {
        # Les petits modeles rendent parfois les champs facultatifs de zim_query
        # obligatoires, puis generent des valeurs invalides. La passerelle expose
        # des schemas courts et delegue au paquet OpenZIM officiel.
        $server = [pscustomobject]@{
            type    = 'stdio'
            command = $OpenZimPythonPath
            args    = @($CompatibilityServerPath) + $ArchivePaths
        }
    }
    else {
        $server = [pscustomobject]@{
            type    = 'stdio'
            command = $UvxPath
            args    = @('openzim-mcp', '--mode', 'advanced') + $ArchivePaths
        }
    }

    $existingServer = $configuration.servers.PSObject.Properties['openzim']
    if ($null -ne $existingServer -and -not $Overwrite) {
        $existingJson = $existingServer.Value | ConvertTo-Json -Compress -Depth 20
        $requestedJson = $server | ConvertTo-Json -Compress -Depth 20
        if ($existingJson -eq $requestedJson) {
            Write-Host "Configuration MCP deja a jour : $configurationPath" -ForegroundColor Green
            return
        }
        throw "Le serveur 'openzim' existe deja avec une configuration differente dans '$configurationPath'. Utilisez -ForceMcpConfig pour le remplacer."
    }

    if ($null -ne $existingServer) {
        $configuration.servers.openzim = $server
    }
    else {
        $configuration.servers |
            Add-Member -MemberType NoteProperty -Name openzim -Value $server
    }

    if ($PSCmdlet.ShouldProcess($configurationPath, 'Ecrire la configuration MCP de VS Code')) {
        if (-not (Test-Path -LiteralPath $vscodeDirectory)) {
            New-Item -ItemType Directory -Path $vscodeDirectory | Out-Null
        }

        $json = $configuration | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText(
            $configurationPath,
            $json + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )
        Write-Host "Configuration MCP ecrite : $configurationPath" -ForegroundColor Green
    }
}
# endregion Fonctions utilitaires

# region Installation et configuration
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Ce script cible Windows. Consultez la documentation OpenZIM MCP pour macOS ou Linux.'
}

if ($DownloadRerankerModels -and -not $WithReranker) {
    throw '-DownloadRerankerModels requiert egalement -WithReranker.'
}

Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '       INSTALLATION DU SERVEUR OPENZIM MCP' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host 'uv gere OpenZIM MCP dans un environnement Python isole.'
Write-Host 'Cette etape ne telecharge aucune archive ZIM.'
if ($ConfigureVSCode) {
    Write-Host "Projet a configurer : $ProjectDirectory"
    Write-Host "Bibliotheque ZIM   : $ZimDirectory"
    Write-Host "Mode MCP           : $Mode"
}

Write-Step 'Verification de uv'
$uvPath = Get-ExecutablePath -Name 'uv.exe'

if ($null -eq $uvPath) {
    $wingetPath = Get-ExecutablePath -Name 'winget.exe'
    if ($null -eq $wingetPath) {
        throw "uv est absent et WinGet est introuvable. Installez 'App Installer' depuis Microsoft Store, puis relancez ce script."
    }

    if ($PSCmdlet.ShouldProcess('astral-sh.uv', 'Installer avec WinGet')) {
        Invoke-NativeCommand -FilePath $wingetPath -ArgumentList @(
            'install', '--id', 'astral-sh.uv', '--exact',
            '--accept-source-agreements', '--accept-package-agreements',
            '--disable-interactivity'
        )
        Update-SessionPath
        $uvPath = Get-ExecutablePath -Name 'uv.exe'
    }
}
else {
    Write-Host "uv deja installe : $uvPath" -ForegroundColor Green
}

if ($null -eq $uvPath) {
    if ($WhatIfPreference) {
        Write-Warning 'Mode WhatIf : uv serait installe avant les etapes suivantes.'
        return
    }
    throw 'uv semble installe, mais uv.exe reste introuvable. Ouvrez un nouveau terminal puis relancez le script.'
}

Invoke-NativeCommand -FilePath $uvPath -ArgumentList @('--version')

Write-Step 'Installation ou mise a jour de OpenZIM MCP'
$requirement = if ($WithReranker) { 'openzim-mcp[reranker]' } else { 'openzim-mcp' }
if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $requirement = "$requirement==$Version"
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    # Les versions recentes de uv retournent le code 1 et ecrivent
    # "No tools installed" lors d'une premiere utilisation. Cet etat est
    # normal : il signifie simplement que openzim-mcp doit etre installe.
    $installedTools = & $uvPath tool list 2>&1 | Out-String
    $toolListExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}

$noUvToolsInstalled = $installedTools -match '(?im)^\s*No tools installed\.?\s*$'
if ($toolListExitCode -ne 0 -and -not $noUvToolsInstalled) {
    throw "Impossible de lire la liste des outils uv.`n$installedTools"
}
$isInstalled = $installedTools -match '(?m)^openzim-mcp\s'
Write-Host $(if ($isInstalled) {
    'OpenZIM MCP est deja gere par uv : recherche d une mise a jour.'
} else {
    'OpenZIM MCP n est pas encore gere par uv : installation initiale.'
}) -ForegroundColor DarkCyan

if ($PSCmdlet.ShouldProcess($requirement, 'Installer ou mettre a jour avec uv')) {
    if ($isInstalled -and -not $WithReranker -and [string]::IsNullOrWhiteSpace($Version)) {
        Invoke-NativeCommand -FilePath $uvPath -ArgumentList @('tool', 'upgrade', 'openzim-mcp')
    }
    else {
        Invoke-NativeCommand -FilePath $uvPath -ArgumentList @('tool', 'install', $requirement)
    }
}

$toolBin = (& $uvPath tool dir --bin 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($toolBin)) {
    throw 'Impossible de determiner le dossier des executables uv.'
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$userPathParts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$normalizedToolBin = $toolBin.TrimEnd('\')
$toolBinIsPersistent = @($userPathParts | ForEach-Object { $_.Trim().TrimEnd('\') }) -contains $normalizedToolBin
if (-not $toolBinIsPersistent -and $PSCmdlet.ShouldProcess($toolBin, 'Ajouter au PATH utilisateur')) {
    $updatedUserPath = @($toolBin) + $userPathParts | Select-Object -Unique
    [Environment]::SetEnvironmentVariable('Path', ($updatedUserPath -join ';'), 'User')
    Write-Host "PATH utilisateur mis a jour : $toolBin" -ForegroundColor Green
}
if (($env:Path -split ';') -notcontains $toolBin) {
    $env:Path = "$toolBin;$env:Path"
}

$openZimPath = Get-ExecutablePath -Name 'openzim-mcp.exe'
$uvxPath = Get-ExecutablePath -Name 'uvx.exe'
if ($null -eq $uvxPath) {
    $uvxPath = Join-Path (Split-Path -Parent $uvPath) 'uvx.exe'
}
$toolDirectory = (& $uvPath tool dir 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($toolDirectory)) {
    throw 'Impossible de determiner le dossier des environnements uv.'
}
$openZimPythonPath = Join-Path $toolDirectory 'openzim-mcp\Scripts\python.exe'
$compatibilityServerPath = Join-Path $repositoryRoot 'scripts\OpenZimCompatServer.py'

if (-not $WhatIfPreference) {
    if ($null -eq $openZimPath) {
        throw "OpenZIM MCP a ete installe, mais 'openzim-mcp.exe' reste introuvable dans '$toolBin'."
    }
    if (-not (Test-Path -LiteralPath $openZimPythonPath -PathType Leaf)) {
        throw "Interpreteur Python OpenZIM introuvable : $openZimPythonPath"
    }
    if (-not (Test-Path -LiteralPath $compatibilityServerPath -PathType Leaf)) {
        throw "Passerelle de compatibilite introuvable : $compatibilityServerPath"
    }

    Write-Step 'Verification de OpenZIM MCP'
    $openZimHelp = (& $openZimPath --help 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $openZimHelp -notmatch 'OpenZIM MCP') {
        throw 'La commande openzim-mcp --help ne repond pas correctement.'
    }
    Write-Host "[OK] Commande OpenZIM MCP valide : $openZimPath" -ForegroundColor Green
    Write-Host "     Environnement Python       : $openZimPythonPath" -ForegroundColor DarkGray

    if ($DownloadRerankerModels) {
        Write-Step 'Telechargement du modele de reranking'
        if ($PSCmdlet.ShouldProcess('Modele de reranking OpenZIM MCP (~1,1 Go)', 'Telecharger')) {
            Invoke-NativeCommand -FilePath $openZimPath -ArgumentList @('download-models')
        }
    }
}

if ($ConfigureVSCode) {
    if ([string]::IsNullOrWhiteSpace($ZimDirectory)) {
        throw '-ConfigureVSCode requiert -ZimDirectory.'
    }

    $resolvedZimDirectory = Resolve-ExistingDirectory -Path $ZimDirectory
    $zimFiles = @(Get-ChildItem -LiteralPath $resolvedZimDirectory -Filter '*.zim' -File -Recurse)
    if ($zimFiles.Count -eq 0) {
        Write-Warning "Aucun fichier .zim trouve dans '$resolvedZimDirectory'. La configuration sera creee, mais les recherches seront vides."
    }

    $archiveDirectories = @($zimFiles.DirectoryName | Select-Object -Unique)
    if ($archiveDirectories.Count -eq 0) {
        $archiveDirectories = @(
            Get-ChildItem -LiteralPath $resolvedZimDirectory -Directory |
                Select-Object -ExpandProperty FullName
        )
    }
    if ($archiveDirectories.Count -eq 0) {
        $archiveDirectories = @($resolvedZimDirectory)
    }

    Write-Step 'Configuration de VS Code'
    if ($Mode -eq 'simple' -and -not $WhatIfPreference) {
        Write-Host 'Verification de la passerelle simplifiee pour les modeles locaux...' -ForegroundColor DarkCyan
        Invoke-NativeCommand `
            -FilePath $openZimPythonPath `
            -ArgumentList (@($compatibilityServerPath, '--self-test') + $archiveDirectories)
    }
    Set-VSCodeMcpConfiguration `
        -WorkspacePath $ProjectDirectory `
        -ArchivePaths $archiveDirectories `
        -UvxPath $uvxPath `
        -OpenZimPythonPath $openZimPythonPath `
        -CompatibilityServerPath $compatibilityServerPath `
        -ToolMode $Mode `
        -Overwrite $ForceMcpConfig.IsPresent

    Write-Step 'Instructions de recherche locale pour l agent IA'
    Set-OpenZimProjectInstructions `
        -WorkspacePath $ProjectDirectory `
        -Confirm:$false `
        -WhatIf:$WhatIfPreference | Out-Null
}

Write-Host "`nInstallation terminee." -ForegroundColor Green
if (-not $ConfigureVSCode) {
    Write-Host "Pour connecter VS Code : .\scripts\Install-OpenZimMcp.ps1 -ZimDirectory 'D:\Kiwix\ZIM' -ConfigureVSCode"
    Write-Host 'Dans le menu principal, utilisez ensuite les options 3, 4 et 5.'
}
# endregion Installation et configuration
