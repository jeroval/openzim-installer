Set-StrictMode -Version Latest
$script:OpenZimLogPath = $null

# region Journalisation structuree
function Initialize-OpenZimLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter()] [ValidateRange(1, 3650)] [int] $RetentionDays = 14,
        [Parameter()] [string] $Prefix = 'openzim'
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -LiteralPath $Directory -Filter "$Prefix-*.log" -File -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -LT $cutoff |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:OpenZimLogPath = Join-Path $Directory "$Prefix-$stamp-$PID.log"
    return $script:OpenZimLogPath
}

function Write-OpenZimLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO', 'WARNING', 'ERROR')] [string] $Level,
        [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9_]+$')] [string] $Event,
        [Parameter(Mandatory)] [string] $Message,
        [Parameter()] [hashtable] $Data
    )

    if ([string]::IsNullOrWhiteSpace($script:OpenZimLogPath)) {
        return
    }

    $record = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        level     = $Level
        event     = $Event
        message   = $Message
    }
    if ($null -ne $Data) {
        $record.data = $Data
    }

    $line = $record | ConvertTo-Json -Compress -Depth 10
    [IO.File]::AppendAllText(
        $script:OpenZimLogPath,
        $line + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}
# endregion Journalisation structuree

# region Verrouillage de la bibliotheque
function Enter-OpenZimMutex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Scope,
        [Parameter()] [ValidateRange(0, 3600)] [int] $TimeoutSeconds = 0
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Scope.ToLowerInvariant())
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').Substring(0, 24)
    }
    finally {
        $sha.Dispose()
    }

    $mutex = [Threading.Mutex]::new($false, "Local\OpenZim-$hash")
    try {
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    }
    catch [Threading.AbandonedMutexException] {
        $acquired = $true
    }

    if (-not $acquired) {
        $mutex.Dispose()
        throw "Une autre instance gere deja cette bibliotheque : $Scope"
    }

    return $mutex
}

function Exit-OpenZimMutex {
    [CmdletBinding()]
    param([Parameter()] [Threading.Mutex] $Mutex)

    if ($null -eq $Mutex) {
        return
    }
    try {
        $Mutex.ReleaseMutex()
    }
    finally {
        $Mutex.Dispose()
    }
}
# endregion Verrouillage de la bibliotheque

# region Instructions IA gerees dans les projets
function Merge-OpenZimManagedContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $ExistingContent,
        [Parameter(Mandatory)] [string] $BeginMarker,
        [Parameter(Mandatory)] [string] $EndMarker,
        [Parameter(Mandatory)] [string] $Body,
        [Parameter()] [AllowEmptyString()] [string] $InitialPrefix = '',
        [Parameter(Mandatory)] [string] $FilePath
    )

    $beginMatches = [regex]::Matches($ExistingContent, [regex]::Escape($BeginMarker)).Count
    $endMatches = [regex]::Matches($ExistingContent, [regex]::Escape($EndMarker)).Count
    if ($beginMatches -ne $endMatches -or $beginMatches -gt 1) {
        throw "Les marqueurs geres sont incomplets ou dupliques dans '$FilePath'. Corrigez-les avant de relancer."
    }

    $managedBlock = $BeginMarker + [Environment]::NewLine +
        $Body.Trim() + [Environment]::NewLine +
        $EndMarker

    if ($beginMatches -eq 1) {
        $beginIndex = $ExistingContent.IndexOf($BeginMarker, [StringComparison]::Ordinal)
        $endIndex = $ExistingContent.IndexOf($EndMarker, $beginIndex, [StringComparison]::Ordinal)
        if ($endIndex -lt $beginIndex) {
            throw "Les marqueurs geres sont dans le mauvais ordre dans '$FilePath'."
        }
        $endIndex += $EndMarker.Length
        return $ExistingContent.Substring(0, $beginIndex) +
            $managedBlock +
            $ExistingContent.Substring($endIndex)
    }

    if ([string]::IsNullOrWhiteSpace($ExistingContent)) {
        $prefix = if ([string]::IsNullOrWhiteSpace($InitialPrefix)) {
            ''
        }
        else {
            $InitialPrefix.Trim() + [Environment]::NewLine + [Environment]::NewLine
        }
        return $prefix + $managedBlock + [Environment]::NewLine
    }

    if (-not [string]::IsNullOrWhiteSpace($InitialPrefix) -and $ExistingContent -notmatch '^\s*---') {
        throw "Le fichier d instructions '$FilePath' existe sans en-tete YAML ni marqueurs OpenZIM. Renommez-le avant de relancer."
    }

    return $ExistingContent.TrimEnd("`r", "`n") +
        [Environment]::NewLine + [Environment]::NewLine +
        $managedBlock + [Environment]::NewLine
}

function Set-OpenZimProjectInstructions {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspacePath
    )

    $workspace = Resolve-Path -LiteralPath $WorkspacePath -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $workspace.Path -PathType Container)) {
        throw "Le chemin n'est pas un dossier de projet : $WorkspacePath"
    }

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $standardsTemplatePath = Join-Path $repositoryRoot 'templates\Development-Standards.instructions.md'
    $guideSourcePath = Join-Path $repositoryRoot 'docs\Guide-Bonnes-Pratiques-Code.md'
    foreach ($requiredFile in @($standardsTemplatePath, $guideSourcePath)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Modele d instructions introuvable : $requiredFile"
        }
    }

    $standardsTemplate = [IO.File]::ReadAllText($standardsTemplatePath)
    $templateMatch = [regex]::Match(
        $standardsTemplate,
        '(?s)\A(---\r?\n.*?\r?\n---)\s*(.*)\z'
    )
    if (-not $templateMatch.Success) {
        throw "Le modele '$standardsTemplatePath' doit contenir un en-tete YAML suivi des instructions."
    }

    $standardsFrontMatter = $templateMatch.Groups[1].Value
    $standardsBody = $templateMatch.Groups[2].Value
    $guideBody = [IO.File]::ReadAllText($guideSourcePath)

    $copilotBody = @'
## Documentation locale OpenZIM

Applique les standards obligatoires de
`.github/instructions/openzim-development-standards.instructions.md` à toute
création, modification, correction ou revue de code.

1. Consulte d'abord le serveur MCP `openzim` avec l'outil `zim_query`.
2. Formule une recherche precise avec les mots de l'erreur et le contexte technique.
3. Appuie la reponse sur les resultats locaux pertinents et indique l'archive ou
   l'article utilise lorsqu'il est disponible.
4. Si la base locale ne contient pas de resultat pertinent, indique-le clairement
   avant de raisonner a partir de tes connaissances generales.
5. Ne presente pas comme certaine une commande ou une API que tu n'as pas pu
   verifier. Pour les informations propres au projet, les fichiers du projet
   restent prioritaires.
'@.Trim()

    $agentPolicyBody = @'
## Politique de développement gérée par OpenZIM

- Applique `.github/instructions/openzim-development-standards.instructions.md`.
- Inspecte les conventions et les fichiers concernés avant toute modification.
- Consulte OpenZIM lorsqu'une API, une syntaxe ou une technologie est incertaine.
- Préserve les changements existants et demande confirmation avant une action irréversible.
- Exécute les validations disponibles et ne prétends jamais avoir exécuté un test non lancé.
- Explique toute dérogation aux standards et termine par un résumé des vérifications.
'@.Trim()

$gitIgnoreBody = @'
# Configuration OpenZIM propre a cette machine
.vscode/mcp.json
.github/copilot-instructions.md

# Bibliotheque et etat d execution locaux
*.zim
*.zim.part
download-plan.json
zim-inventory.json
catalog-development-candidates.json
'@.Trim()

    $artifacts = @(
        [pscustomobject]@{
            Path          = Join-Path $workspace.Path '.github\copilot-instructions.md'
            BeginMarker   = '<!-- openzim-mcp:begin -->'
            EndMarker     = '<!-- openzim-mcp:end -->'
            Body          = $copilotBody
            InitialPrefix = ''
            Label         = 'Instructions generales OpenZIM'
        }
        [pscustomobject]@{
            Path          = Join-Path $workspace.Path '.github\instructions\openzim-development-standards.instructions.md'
            BeginMarker   = '<!-- openzim-standards:begin -->'
            EndMarker     = '<!-- openzim-standards:end -->'
            Body          = $standardsBody
            InitialPrefix = $standardsFrontMatter
            Label         = 'Standards de developpement IA'
        }
        [pscustomobject]@{
            Path          = Join-Path $workspace.Path 'docs\ai\Guide-Bonnes-Pratiques-Code.md'
            BeginMarker   = '<!-- openzim-guide:begin -->'
            EndMarker     = '<!-- openzim-guide:end -->'
            Body          = $guideBody
            InitialPrefix = ''
            Label         = 'Guide complet de bonnes pratiques'
        }
        [pscustomobject]@{
            Path          = Join-Path $workspace.Path 'AGENTS.md'
            BeginMarker   = '<!-- openzim-agent-policy:begin -->'
            EndMarker     = '<!-- openzim-agent-policy:end -->'
            Body          = $agentPolicyBody
            InitialPrefix = ''
            Label         = 'Politique multi-agent'
        }
        [pscustomobject]@{
            Path          = Join-Path $workspace.Path '.gitignore'
            BeginMarker   = '# openzim-local:begin'
            EndMarker     = '# openzim-local:end'
            Body          = $gitIgnoreBody
            InitialPrefix = ''
            Label         = 'Regles Git locales OpenZIM'
        }
    )

    foreach ($artifact in $artifacts) {
        $existingContent = if (Test-Path -LiteralPath $artifact.Path -PathType Leaf) {
            [IO.File]::ReadAllText($artifact.Path)
        }
        else {
            ''
        }
        $newContent = Merge-OpenZimManagedContent `
            -ExistingContent $existingContent `
            -BeginMarker $artifact.BeginMarker `
            -EndMarker $artifact.EndMarker `
            -Body $artifact.Body `
            -InitialPrefix $artifact.InitialPrefix `
            -FilePath $artifact.Path

        if ($newContent -eq $existingContent) {
            Write-Host "$($artifact.Label) deja a jour : $($artifact.Path)" -ForegroundColor Green
            continue
        }

        if ($PSCmdlet.ShouldProcess($artifact.Path, "Creer ou actualiser : $($artifact.Label)")) {
            $parentDirectory = Split-Path -Parent $artifact.Path
            if (-not (Test-Path -LiteralPath $parentDirectory)) {
                New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
            }
            [IO.File]::WriteAllText(
                $artifact.Path,
                $newContent,
                [Text.UTF8Encoding]::new($false)
            )
            Write-Host "$($artifact.Label) ecrit : $($artifact.Path)" -ForegroundColor Green
        }
    }

    return (Join-Path $workspace.Path '.github\copilot-instructions.md')
}
# endregion Instructions IA gerees dans les projets

Export-ModuleMember -Function Initialize-OpenZimLog, Write-OpenZimLog, Enter-OpenZimMutex, Exit-OpenZimMutex, Set-OpenZimProjectInstructions
