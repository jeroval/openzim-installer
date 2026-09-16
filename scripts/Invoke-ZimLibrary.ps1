#requires -Version 5.1

<#
.SYNOPSIS
Decouvre, telecharge et met a jour une bibliotheque ZIM pour un agent local.

.DESCRIPTION
Lit le catalogue Kiwix et le manifeste `config/ZimSources.json`, choisit la version
la plus recente de chaque source pertinente et construit un panier qui ne
depasse pas le budget. Les variantes `nopic` sont preferees lorsqu'elles sont
disponibles. Les telechargements incomplets utilisent l'extension `.part` afin
de pouvoir reprendre apres une interruption.

.PARAMETER Action
`Plan` calcule sans telecharger. `Download` applique le plan. `Update` recherche
les nouvelles editions. `Status` inventorie le disque. `Discover` exporte les
documentations techniques trouvees dans le catalogue.

.PARAMETER MaxLibrarySizeGB
Plafond strict du panier ZIM. Il ne comprend ni Ollama ni ses modeles.

.PARAMETER IncludeOptional
Autorise les sources marquees optionnelles, comme certaines documentations de
frameworks ou langages. Elles restent soumises au budget.

.PARAMETER RemovePrevious
Apres validation d'une nouvelle edition, supprime l'ancienne edition locale de
la meme source. Sans ce parametre, les anciennes archives sont conservees.

.EXAMPLE
.\scripts\Invoke-ZimLibrary.ps1 -Action Plan

.EXAMPLE
.\scripts\Invoke-ZimLibrary.ps1 -Action Download -IncludeOptional

.EXAMPLE
.\scripts\Invoke-ZimLibrary.ps1 -Action Update
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath,

    [Parameter()]
    [ValidateSet('Discover', 'Plan', 'Download', 'Update', 'Status')]
    [string] $Action = 'Plan',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $LibraryRoot = 'C:\AI\Knowledge\ZIM',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ManifestPath,

    [Parameter()]
    [uri] $CatalogUri = 'https://library.kiwix.org/catalog/v2/entries?lang=eng,fra&count=-1',

    [Parameter()]
    [string] $CatalogFile,

    [Parameter()]
    [switch] $IncludeOptional,

    [Parameter()]
    [switch] $PreferNoPictures = $true,

    [Parameter()]
    [switch] $SkipChecksum,

    [Parameter()]
    [switch] $RemovePrevious,

    [Parameter()]
    [ValidateRange(1, 4096)]
    [int] $MaxLibrarySizeGB = 50,

    [Parameter()]
    [ValidateSet('general', 'web', 'systems', 'data-ai', 'security')]
    [string] $UsageProfile = 'general',

    [Parameter()]
    [switch] $AllowBudgetOverflow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# region Initialisation de la configuration
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repositoryRoot 'config\OpenZim.Settings.json'
}
$commonModule = Join-Path $repositoryRoot 'modules\OpenZim.Common.psm1'
Import-Module $commonModule -Force

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration introuvable : $ConfigPath"
}
$configuration = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $PSBoundParameters.ContainsKey('LibraryRoot')) {
    $LibraryRoot = [Environment]::ExpandEnvironmentVariables([string] $configuration.libraryRoot)
}
if (-not $PSBoundParameters.ContainsKey('ManifestPath')) {
    $configuredManifest = [Environment]::ExpandEnvironmentVariables([string] $configuration.manifestPath)
    $ManifestPath = if ([IO.Path]::IsPathRooted($configuredManifest)) {
        $configuredManifest
    }
    else {
        Join-Path (Split-Path -Parent $ConfigPath) $configuredManifest
    }
}
if (-not $PSBoundParameters.ContainsKey('CatalogUri')) {
    $CatalogUri = [uri] $configuration.catalogUri
}
if (-not $PSBoundParameters.ContainsKey('MaxLibrarySizeGB')) {
    $MaxLibrarySizeGB = [int] $configuration.maxLibrarySizeGB
}
if (-not $PSBoundParameters.ContainsKey('UsageProfile') -and
    $null -ne $configuration.PSObject.Properties['usageProfile']) {
    $UsageProfile = [string] $configuration.usageProfile
}
if (-not $PSBoundParameters.ContainsKey('IncludeOptional') -and [bool] $configuration.includeOptional) {
    $IncludeOptional = $true
}
if (-not $PSBoundParameters.ContainsKey('PreferNoPictures')) {
    $PreferNoPictures = [bool] $configuration.preferNoPictures
}
if (-not $PSBoundParameters.ContainsKey('SkipChecksum') -and -not [bool] $configuration.verifyChecksum) {
    $SkipChecksum = $true
}

$reserveFreeSpaceGB = [int] $configuration.reserveFreeSpaceGB
$downloadRetryCount = [int] $configuration.download.retryCount
$downloadRetryDelaySeconds = [int] $configuration.download.retryDelaySeconds
$configuredLogDirectory = [string] $configuration.logs.directory
$logDirectory = if ([IO.Path]::IsPathRooted($configuredLogDirectory)) {
    $configuredLogDirectory
}
else {
    Join-Path $repositoryRoot $configuredLogDirectory
}
$logPath = Initialize-OpenZimLog `
    -Directory $logDirectory `
    -RetentionDays ([int] $configuration.logs.retentionDays) `
    -Prefix 'zim-library'
$categories = @('Programming', 'Web', 'Systems', 'DevOps', 'Database', 'Security', 'General')
# endregion Initialisation de la configuration

# region Catalogue, selection et telechargement
function Write-Step {
    param([string] $Message)
    Write-OpenZimLog -Level INFO -Event 'step' -Message $Message
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Format-ByteSize {
    param([long] $Bytes)
    if ($Bytes -ge 1TB) { return '{0:N2} To' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} Go' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} Mo' -f ($Bytes / 1MB) }
    return '{0:N0} octets' -f $Bytes
}

function Get-ProfileAffinity {
    param(
        [Parameter(Mandatory)] [string] $Profile,
        [Parameter(Mandatory)] [string] $Category
    )

    # Le score de base exprime l'utilite generale de la source. Ce bonus ne
    # supprime aucune source : il fait seulement remonter les connaissances les
    # plus proches du besoin exprime lorsque le budget impose des choix.
    $bonuses = @{
        general = @{}
        web = @{ Web = 30; Programming = 12; Database = 8; Security = 4 }
        systems = @{ Systems = 30; DevOps = 28; Security = 15; Database = 5 }
        'data-ai' = @{ Database = 25; Programming = 20; Systems = 5 }
        security = @{ Security = 35; Systems = 20; DevOps = 10; Programming = 5 }
    }
    $profileBonuses = $bonuses[$Profile]
    if ($null -ne $profileBonuses -and $profileBonuses.ContainsKey($Category)) {
        return [int] $profileBonuses[$Category]
    }
    return 0
}

function New-LibraryLayout {
    param([string] $Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }
    foreach ($category in $categories) {
        $path = Join-Path $Root $category
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Get-CatalogEntries {
    param([uri] $Uri, [string] $File)

    if (-not [string]::IsNullOrWhiteSpace($File)) {
        Write-Step "Lecture du catalogue local : $File"
        [xml] $document = Get-Content -LiteralPath $File -Raw -Encoding UTF8
    }
    else {
        Write-Step "Lecture du catalogue Kiwix : $Uri"
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -MaximumRedirection 10
        [xml] $document = $response.Content
    }

    $namespaces = [Xml.XmlNamespaceManager]::new($document.NameTable)
    $namespaces.AddNamespace('atom', 'http://www.w3.org/2005/Atom')
    $entries = $document.SelectNodes('//atom:entry', $namespaces)

    foreach ($entry in $entries) {
        $downloadLink = $entry.SelectNodes('atom:link', $namespaces) |
            Where-Object {
                $_.type -eq 'application/x-zim' -and
                $_.rel -match 'acquisition'
            } |
            Select-Object -First 1

        if ($null -eq $downloadLink -or [string]::IsNullOrWhiteSpace($downloadLink.href)) {
            continue
        }

        $downloadUri = [string] $downloadLink.href -replace '\.meta4$', ''
        $fileName = [Uri]::UnescapeDataString([IO.Path]::GetFileName(([uri] $downloadUri).AbsolutePath))
        $updatedNode = $entry.SelectSingleNode('atom:updated', $namespaces)
        $titleNode = $entry.SelectSingleNode('atom:title', $namespaces)

        [pscustomobject]@{
            FileName = $fileName
            Uri      = $downloadUri
            Meta4Uri = [string] $downloadLink.href
            Size     = if ($downloadLink.length) { [long] $downloadLink.length } else { 0L }
            Updated  = if ($null -ne $updatedNode) { [datetime] $updatedNode.InnerText } else { [datetime]::MinValue }
            Title    = if ($null -ne $titleNode) { $titleNode.InnerText } else { $fileName }
        }
    }
}

function Get-LatestSelection {
    param(
        [object[]] $Catalog,
        [object[]] $Sources,
        [bool] $UseOptional,
        [bool] $UseNoPictures,
        [int] $BudgetGB
    )

    foreach ($source in $Sources) {
        $minimumBudgetGB = if ($null -ne $source.PSObject.Properties['minimumBudgetGB']) {
            [int] $source.minimumBudgetGB
        }
        elseif ([bool] $source.required) {
            0
        }
        else {
            100
        }

        if (-not [bool] $source.required -and -not $UseOptional -and $BudgetGB -lt $minimumBudgetGB) {
            continue
        }

        $matches = @($Catalog | Where-Object { $_.FileName -match [string] $source.pattern })
        if ($matches.Count -eq 0) {
            Write-Warning "Archive introuvable dans le catalogue : $($source.title)"
            continue
        }

        if ($UseNoPictures) {
            $noPictureMatches = @($matches | Where-Object { $_.FileName -match '(^|_)nopic(_|\.)' })
            if ($noPictureMatches.Count -gt 0) {
                $matches = $noPictureMatches
            }
        }

        $latest = $matches |
            Sort-Object -Property @{ Expression = 'Updated'; Descending = $true },
                                  @{ Expression = 'FileName'; Descending = $true } |
            Select-Object -First 1

        [pscustomobject]@{
            Id       = [string] $source.id
            Title    = [string] $source.title
            Category = [string] $source.category
            Required = [bool] $source.required
            Priority = if ($null -ne $source.PSObject.Properties['priority']) { [int] $source.priority } else { 100 }
            Relevance = if ($null -ne $source.PSObject.Properties['relevance']) { [int] $source.relevance } else { 50 }
            ProfileAffinity = Get-ProfileAffinity -Profile $UsageProfile -Category ([string] $source.category)
            MinimumBudgetGB = $minimumBudgetGB
            ExclusiveGroup = if ($null -ne $source.PSObject.Properties['exclusiveGroup']) { [string] $source.exclusiveGroup } else { '' }
            VariantRank = if ($null -ne $source.PSObject.Properties['variantRank']) { [int] $source.variantRank } else { 0 }
            FileName = $latest.FileName
            Uri      = $latest.Uri
            Size     = $latest.Size
            Updated  = $latest.Updated
        }
    }
}

function Get-ExpectedSha256 {
    param([string] $DownloadUri)

    try {
        $checksumText = (Invoke-WebRequest -Uri "$DownloadUri.sha256" -UseBasicParsing).Content
        $match = [regex]::Match([string] $checksumText, '(?i)\b[0-9a-f]{64}\b')
        if ($match.Success) {
            return $match.Value.ToLowerInvariant()
        }
    }
    catch {
        Write-Warning "Somme SHA-256 indisponible pour $DownloadUri"
    }
    return $null
}

function Invoke-ResumableDownload {
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Destination,
        [Parameter(Mandatory)] [long] $ExpectedSize,
        [Parameter(Mandatory)] [bool] $VerifyChecksum
    )

    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination
        if ($ExpectedSize -eq 0 -or $existing.Length -eq $ExpectedSize) {
            Write-OpenZimLog -Level INFO -Event 'download_skipped' -Message 'Archive deja presente' -Data @{ path = $Destination; size = $existing.Length }
            Write-Host "Deja present : $($existing.Name)" -ForegroundColor DarkGreen
            return
        }
        Write-Warning "Le fichier existant a une taille incorrecte et sera retelecharge : $Destination"
    }

    $curl = Get-Command 'curl.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $curl) {
        throw 'curl.exe est requis pour reprendre les gros telechargements interrompus.'
    }

    $partialPath = "$Destination.part"
    Write-OpenZimLog -Level INFO -Event 'download_started' -Message 'Debut ou reprise du telechargement' -Data @{ uri = $Uri; destination = $Destination; partial = $partialPath }
    & $curl.Source @(
        '--fail', '--location', '--continue-at', '-',
        '--retry', [string] $downloadRetryCount, '--retry-delay', [string] $downloadRetryDelaySeconds,
        '--output', $partialPath, $Uri
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Echec du telechargement (code curl $LASTEXITCODE). Le fichier partiel est conserve : $partialPath"
    }

    $partial = Get-Item -LiteralPath $partialPath
    $hashValidated = $false
    if ($VerifyChecksum) {
        $expectedHash = Get-ExpectedSha256 -DownloadUri $Uri
        if ($null -ne $expectedHash) {
            Write-Host 'Verification SHA-256...'
            $actualHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $expectedHash) {
                throw "Somme SHA-256 invalide pour '$partialPath'. Le fichier partiel est conserve pour diagnostic."
            }
            $hashValidated = $true
        }
    }

    if ($ExpectedSize -gt 0 -and $partial.Length -ne $ExpectedSize) {
        if (-not $hashValidated) {
            throw "Taille invalide pour '$partialPath' : $($partial.Length) au lieu de $ExpectedSize octets, et aucune somme SHA-256 n'a permis de valider le fichier."
        }
        Write-Warning "La taille du catalogue differe de $($ExpectedSize - $partial.Length) octet(s), mais la somme SHA-256 est valide."
        Write-OpenZimLog -Level WARNING -Event 'catalog_size_mismatch' -Message 'Taille du catalogue differente, archive validee par SHA-256' -Data @{
            path = $partialPath
            expectedSize = $ExpectedSize
            actualSize = $partial.Length
        }
    }

    Move-Item -LiteralPath $partialPath -Destination $Destination -Force
    Write-OpenZimLog -Level INFO -Event 'download_completed' -Message 'Archive telechargee et validee' -Data @{ uri = $Uri; destination = $Destination; size = $partial.Length }
}

function Remove-OlderArchives {
    param(
        [object] $Selected,
        [string] $Root
    )

    $source = $sources | Where-Object { $_.id -eq $Selected.Id } | Select-Object -First 1
    $categoryPath = Join-Path $Root $Selected.Category
    Get-ChildItem -LiteralPath $categoryPath -Filter '*.zim' -File |
        Where-Object {
            $_.Name -match [string] $source.pattern -and
            $_.Name -ne $Selected.FileName
        } |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Supprimer une ancienne archive ZIM')) {
                Remove-Item -LiteralPath $_.FullName -Force
                Write-Host "Ancienne version supprimee : $($_.Name)"
            }
        }
}
# endregion Catalogue, selection et telechargement

# region Execution de l action demandee
$mutex = $null
try {
    $mutex = Enter-OpenZimMutex -Scope ([IO.Path]::GetFullPath($LibraryRoot))
    Write-OpenZimLog -Level INFO -Event 'session_started' -Message 'Execution du gestionnaire ZIM' -Data @{
        action = $Action
        libraryRoot = $LibraryRoot
        maxLibrarySizeGB = $MaxLibrarySizeGB
        processId = $PID
    }

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Ce script cible Windows.'
    }
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest introuvable : $ManifestPath"
    }

$parsedSources = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sources = @($parsedSources | ForEach-Object { $_ })
if ($Action -eq 'Status') {
    if (-not (Test-Path -LiteralPath $LibraryRoot)) {
        Write-Host "Bibliotheque absente : $LibraryRoot"
        return
    }

    $localFiles = @(Get-ChildItem -LiteralPath $LibraryRoot -Filter '*.zim' -File -Recurse)
    $localFiles |
        Select-Object Name, DirectoryName, @{ Name = 'Size'; Expression = { Format-ByteSize $_.Length } }, LastWriteTime |
        Format-Table -AutoSize
    $totalLocalBytes = if ($localFiles.Count -eq 0) {
        0
    }
    else {
        [long] (($localFiles | Measure-Object Length -Sum).Sum)
    }
    Write-Host "`n$($localFiles.Count) archive(s), $(Format-ByteSize $totalLocalBytes)."
    return
}

New-LibraryLayout -Root $LibraryRoot
$catalog = @(Get-CatalogEntries -Uri $CatalogUri -File $CatalogFile)
if ($catalog.Count -eq 0) {
    throw 'Le catalogue Kiwix est vide ou son format a change.'
}

if ($Action -eq 'Discover') {
    $developmentCandidates = @($catalog |
        Where-Object {
            $_.FileName -match '(?i)(devdocs|docs\.|developer\.|programming|software|bootstrap|dart|python|javascript|typescript|rust|golang|kotlin|java|database|devops|security)'
        } |
        Sort-Object Updated -Descending)

    $discoveryPath = Join-Path $LibraryRoot 'catalog-development-candidates.json'
    $developmentCandidates |
        Select-Object FileName, Title, Updated, Size, Uri |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $discoveryPath -Encoding UTF8

    $developmentCandidates |
        Select-Object -First 100 FileName, Updated, @{ Name = 'Size'; Expression = { Format-ByteSize $_.Size } } |
        Format-Table -AutoSize
    Write-Host "`n$($developmentCandidates.Count) candidat(s). Catalogue complet : $discoveryPath" -ForegroundColor Green
    return
}

$catalogSelection = @(Get-LatestSelection `
    -Catalog $catalog `
    -Sources $sources `
    -UseOptional $IncludeOptional.IsPresent `
    -UseNoPictures $PreferNoPictures.IsPresent `
    -BudgetGB $MaxLibrarySizeGB)

if ($catalogSelection.Count -eq 0) {
    throw 'Aucune archive du manifest ne correspond au catalogue Kiwix actuel.'
}

$variantSelection = [Collections.Generic.List[object]]::new()
$exclusiveGroups = @($catalogSelection |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.ExclusiveGroup) } |
    Group-Object ExclusiveGroup)

$ungroupedSelection = @($catalogSelection | Where-Object { [string]::IsNullOrWhiteSpace($_.ExclusiveGroup) })
foreach ($item in $ungroupedSelection) {
    $variantSelection.Add($item)
}
foreach ($group in $exclusiveGroups) {
    $groupPriority = ($group.Group | Measure-Object Priority -Minimum).Minimum
    $bytesReservedBeforeGroup = 0L
    foreach ($earlierItem in @($ungroupedSelection | Where-Object { $_.Priority -lt $groupPriority } | Sort-Object Priority)) {
        if (($bytesReservedBeforeGroup + $earlierItem.Size) -le ([long] $MaxLibrarySizeGB * 1GB)) {
            $bytesReservedBeforeGroup += $earlierItem.Size
        }
    }
    $availableForVariant = ([long] $MaxLibrarySizeGB * 1GB) - $bytesReservedBeforeGroup
    $bestVariant = $group.Group |
        Where-Object { $_.Size -le $availableForVariant } |
        Sort-Object -Property @{ Expression = 'VariantRank'; Descending = $true },
                              @{ Expression = 'Updated'; Descending = $true } |
        Select-Object -First 1
    if ($null -ne $bestVariant) {
        $variantSelection.Add($bestVariant)
    }
}

$budgetBytes = [long] $MaxLibrarySizeGB * 1GB
$selectedBytes = 0L
$budgetSelection = foreach ($item in ($variantSelection | Sort-Object @{ Expression = { $_.Relevance + $_.ProfileAffinity }; Descending = $true }, Priority, Title)) {
    $fitsBudget = ($selectedBytes + $item.Size) -le $budgetBytes
    $included = $AllowBudgetOverflow.IsPresent -or $fitsBudget
    if ($included) {
        $selectedBytes += $item.Size
    }

    [pscustomobject]@{
        Id           = $item.Id
        Title        = $item.Title
        Category     = $item.Category
        Required     = $item.Required
        Priority     = $item.Priority
        Relevance    = $item.Relevance
        ProfileAffinity = $item.ProfileAffinity
        MinimumBudgetGB = $item.MinimumBudgetGB
        ExclusiveGroup = $item.ExclusiveGroup
        VariantRank  = $item.VariantRank
        FileName     = $item.FileName
        Uri          = $item.Uri
        Size         = $item.Size
        Updated      = $item.Updated
        Included     = $included
        BudgetReason = if ($included) {
            'Inclus'
        }
        elseif ($item.Size -gt $budgetBytes) {
            "Archive seule > $MaxLibrarySizeGB Go"
        }
        else {
            "Depasse le solde du budget de $MaxLibrarySizeGB Go"
        }
    }
}

$selection = @($budgetSelection | Where-Object Included)
$excludedSelection = @($budgetSelection | Where-Object { -not $_.Included })

$plan = foreach ($item in $budgetSelection) {
    $destination = Join-Path (Join-Path $LibraryRoot $item.Category) $item.FileName
    [pscustomobject]@{
        Priorite    = $item.Priority
        Pertinence  = $item.Relevance
        Affinite     = $item.ProfileAffinity
        Source      = $item.Title
        Category    = $item.Category
        Version     = $item.Updated.ToString('yyyy-MM-dd')
        Size        = Format-ByteSize $item.Size
        SizeBytes   = $item.Size
        Included    = $item.Included
        MotifBudget = $item.BudgetReason
        Etat        = if (-not $item.Included) {
            "EXCLU : $($item.BudgetReason)"
        }
        elseif (Test-Path -LiteralPath $destination) {
            'Present'
        }
        else {
            'A telecharger'
        }
        FileName    = $item.FileName
        Destination = $destination
    }
}

$plan | Select-Object Priorite, Pertinence, Affinite, Source, Category, Version, Size, Etat, FileName | Format-Table -AutoSize -Wrap
$bytesToDownload = ($selection | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path (Join-Path $LibraryRoot $_.Category) $_.FileName))
} | Measure-Object Size -Sum).Sum
Write-Host "`nTaille du pack selectionne : $(Format-ByteSize $selectedBytes) / $MaxLibrarySizeGB Go"
Write-Host "Volume restant a telecharger : $(Format-ByteSize $bytesToDownload)"
Write-Host "Profil automatique : les variantes et sources sont adaptees au budget de $MaxLibrarySizeGB Go." -ForegroundColor DarkCyan
Write-Host "Priorite d usage    : $UsageProfile (la colonne Affinite indique le bonus applique)." -ForegroundColor DarkCyan
if ($excludedSelection.Count -gt 0) {
    Write-Warning "$($excludedSelection.Count) archive(s) exclue(s) pour respecter le budget. Consultez le tableau et download-plan.json."
}

if ($Action -eq 'Plan') {
    $planPath = Join-Path $LibraryRoot 'download-plan.json'
    $planTemporaryPath = "$planPath.tmp"
    $plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planTemporaryPath -Encoding UTF8
    Move-Item -LiteralPath $planTemporaryPath -Destination $planPath -Force
    Write-OpenZimLog -Level INFO -Event 'plan_saved' -Message 'Plan de telechargement enregistre' -Data @{ path = $planPath; selectedBytes = $selectedBytes; budgetBytes = $budgetBytes }
    Write-Host "Plan enregistre : $planPath" -ForegroundColor Green
    return
}

$driveName = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $LibraryRoot).Path).TrimEnd('\').TrimEnd(':')
$freeBytes = (Get-PSDrive -Name $driveName).Free
$requiredFreeBytes = $bytesToDownload + ([long] $reserveFreeSpaceGB * 1GB)
if ($freeBytes -lt $requiredFreeBytes) {
    throw "Espace insuffisant : $(Format-ByteSize $freeBytes) libres, mais $(Format-ByteSize $requiredFreeBytes) recommandes."
}

$downloadFailures = [Collections.Generic.List[object]]::new()
foreach ($item in $selection) {
    $destination = Join-Path (Join-Path $LibraryRoot $item.Category) $item.FileName
    try {
        if ($PSCmdlet.ShouldProcess($destination, "Telecharger $($item.Uri)")) {
            Write-Step "Telechargement : $($item.Title)"
            Invoke-ResumableDownload `
                -Uri $item.Uri `
                -Destination $destination `
                -ExpectedSize $item.Size `
                -VerifyChecksum (-not $SkipChecksum.IsPresent)
        }

        if ($Action -eq 'Update' -and $RemovePrevious -and (Test-Path -LiteralPath $destination)) {
            Remove-OlderArchives -Selected $item -Root $LibraryRoot
        }
    }
    catch {
        $failure = [pscustomobject]@{
            id = $item.Id
            title = $item.Title
            destination = $destination
            message = $_.Exception.Message
        }
        $downloadFailures.Add($failure)
        Write-Warning "Echec pour '$($item.Title)' : $($_.Exception.Message) Passage a l'archive suivante."
        Write-OpenZimLog -Level ERROR -Event 'download_failed' -Message $_.Exception.Message -Data @{
            id = $item.Id
            title = $item.Title
            destination = $destination
        }
    }
}

$inventoryPath = Join-Path $LibraryRoot 'zim-inventory.json'
$inventoryTemporaryPath = "$inventoryPath.tmp"
$inventoryArchives = foreach ($item in $selection) {
    $localPath = Join-Path (Join-Path $LibraryRoot $item.Category) $item.FileName
    $localItem = Get-Item -LiteralPath $localPath -ErrorAction SilentlyContinue
    [pscustomobject]@{
        id           = $item.Id
        title        = $item.Title
        category     = $item.Category
        fileName     = $item.FileName
        sourceUri    = $item.Uri
        catalogDate  = $item.Updated.ToUniversalTime().ToString('o')
        expectedSize = $item.Size
        localPath    = $localPath
        present      = $null -ne $localItem
        actualSize   = if ($null -ne $localItem) { $localItem.Length } else { 0L }
        sizeVerified = $null -ne $localItem -and ($item.Size -eq 0 -or $localItem.Length -eq $item.Size)
    }
}
$inventory = [ordered]@{
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    libraryRoot    = [IO.Path]::GetFullPath($LibraryRoot)
    budgetBytes    = $budgetBytes
    selectedBytes  = $selectedBytes
    logPath        = $logPath
    failedDownloads = @($downloadFailures)
    archives       = @($inventoryArchives)
}
$inventory | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inventoryTemporaryPath -Encoding UTF8
Move-Item -LiteralPath $inventoryTemporaryPath -Destination $inventoryPath -Force
Write-OpenZimLog -Level INFO -Event 'inventory_saved' -Message 'Inventaire enregistre' -Data @{ path = $inventoryPath; archives = $selection.Count }
Write-Host "`nBibliotheque traitee. Inventaire : $inventoryPath" -ForegroundColor Green
if ($downloadFailures.Count -gt 0) {
    Write-Warning "$($downloadFailures.Count) archive(s) n'ont pas pu etre telechargees. Les autres archives ont tout de meme ete traitees."
    $downloadFailures | Select-Object title, message | Format-Table -AutoSize -Wrap
}
}
catch {
    Write-OpenZimLog -Level ERROR -Event 'unhandled_error' -Message $_.Exception.Message -Data @{ action = $Action; processId = $PID }
    throw
}
finally {
    if ($null -ne $mutex) {
        Write-OpenZimLog -Level INFO -Event 'session_finished' -Message 'Fin du gestionnaire ZIM' -Data @{ action = $Action; processId = $PID }
        Exit-OpenZimMutex -Mutex $mutex
    }
}
# endregion Execution de l action demandee
