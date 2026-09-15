Set-StrictMode -Version Latest
$script:OpenZimLogPath = $null

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

    $githubDirectory = Join-Path $workspace.Path '.github'
    $instructionsPath = Join-Path $githubDirectory 'copilot-instructions.md'
    $beginMarker = '<!-- openzim-mcp:begin -->'
    $endMarker = '<!-- openzim-mcp:end -->'
    $managedBlock = @'
<!-- openzim-mcp:begin -->
## Documentation locale OpenZIM

Pour toute question concernant une API, une syntaxe, une erreur, une bibliotheque,
un langage, un systeme ou une technologie :

1. Consulte d'abord le serveur MCP `openzim` avec l'outil `zim_query`.
2. Formule une recherche precise avec les mots de l'erreur et le contexte technique.
3. Appuie la reponse sur les resultats locaux pertinents et indique l'archive ou
   l'article utilise lorsqu'il est disponible.
4. Si la base locale ne contient pas de resultat pertinent, indique-le clairement
   avant de raisonner a partir de tes connaissances generales.
5. Ne presente pas comme certaine une commande ou une API que tu n'as pas pu
   verifier. Pour les informations propres au projet, les fichiers du projet
   restent prioritaires.
<!-- openzim-mcp:end -->
'@.Trim()

    $existingContent = ''
    if (Test-Path -LiteralPath $instructionsPath) {
        $existingContent = [IO.File]::ReadAllText($instructionsPath)
    }

    $beginMatches = [regex]::Matches($existingContent, [regex]::Escape($beginMarker)).Count
    $endMatches = [regex]::Matches($existingContent, [regex]::Escape($endMarker)).Count
    if ($beginMatches -ne $endMatches -or $beginMatches -gt 1) {
        throw "Les marqueurs OpenZIM sont incomplets ou dupliques dans '$instructionsPath'. Corrigez-les avant de relancer."
    }

    if ($beginMatches -eq 1) {
        $beginIndex = $existingContent.IndexOf($beginMarker, [StringComparison]::Ordinal)
        $endIndex = $existingContent.IndexOf($endMarker, $beginIndex, [StringComparison]::Ordinal)
        if ($endIndex -lt $beginIndex) {
            throw "Les marqueurs OpenZIM sont dans le mauvais ordre dans '$instructionsPath'."
        }
        $endIndex += $endMarker.Length
        $newContent = $existingContent.Substring(0, $beginIndex) +
            $managedBlock +
            $existingContent.Substring($endIndex)
    }
    elseif ([string]::IsNullOrWhiteSpace($existingContent)) {
        $newContent = $managedBlock + [Environment]::NewLine
    }
    else {
        $newContent = $existingContent.TrimEnd("`r", "`n") +
            [Environment]::NewLine + [Environment]::NewLine +
            $managedBlock + [Environment]::NewLine
    }

    if ($newContent -eq $existingContent) {
        Write-Host "Instructions OpenZIM deja a jour : $instructionsPath" -ForegroundColor Green
        return $instructionsPath
    }

    if ($PSCmdlet.ShouldProcess($instructionsPath, 'Creer ou actualiser les instructions OpenZIM du projet')) {
        if (-not (Test-Path -LiteralPath $githubDirectory)) {
            New-Item -ItemType Directory -Path $githubDirectory -Force | Out-Null
        }
        [IO.File]::WriteAllText(
            $instructionsPath,
            $newContent,
            [Text.UTF8Encoding]::new($false)
        )
        Write-Host "Instructions OpenZIM ecrites : $instructionsPath" -ForegroundColor Green
    }

    return $instructionsPath
}

Export-ModuleMember -Function Initialize-OpenZimLog, Write-OpenZimLog, Enter-OpenZimMutex, Exit-OpenZimMutex, Set-OpenZimProjectInstructions
