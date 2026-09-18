#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LocalCodex.Common.psm1')

function Get-LocalCodexModel {
    param([Parameter(Mandatory)] $Settings)
    $catalog = Read-LocalCodexJson $Settings.CatalogPath
    if ($catalog.schemaVersion -ne 1) { throw 'Catalogue non supporte.' }
    $models = @($catalog.models | Where-Object id -EQ $Settings.model.id)
    if ($models.Count -ne 1) { throw 'Le modele doit correspondre a une entree unique du catalogue.' }
    $model = $models[0]
    if ($model.family -ne 'Qwen' -or $model.status -notin @('candidate','certified','deprecated','unsupported')) {
        throw 'Famille ou statut de modele invalide.'
    }
    if ($model.status -in @('deprecated','unsupported')) { throw 'Ce modele ne peut pas devenir un nouveau candidat.' }
    if ($model.ollamaTag -notmatch '^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$' -or $model.ollamaTag -match ':latest$') {
        throw 'Un tag explicite autre que latest est obligatoire.'
    }
    if (-not $model.capabilities.tools) { throw 'Le modele ne declare pas le support des outils.' }
    if (-not $model.capabilities.thinking) { throw 'Le modele ne declare pas le support du raisonnement.' }
    return $model
}

function Get-LocalCodexModelChoices {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)] $Hardware)
    $catalog = Read-LocalCodexJson $Settings.CatalogPath
    $ram = [double] $Hardware.ramTotalGB
    $vram = if ($null -eq $Hardware.vramGB) { 0.0 } else { [double] $Hardware.vramGB }
    $sharedGraphics = -not $Hardware.vramReliable -or $vram -lt 2
    $sharedModelLimit = if ($ram -ge 32) { 9.65 } elseif ($ram -ge 16) { 4.0 } elseif ($ram -ge 8) { 2.0 } else { 0.8 }
    $choices = foreach ($entry in @($catalog.models | Where-Object {
        $_.family -eq 'Qwen' -and $_.generation -eq '3.5' -and
        $_.parametersBillions -le 9.65 -and $_.status -notin @('deprecated','unsupported')
    })) {
        $ramOk = $ram -ge ([double] $entry.hardware.minimumRamGB * 0.95)
        $gpuOk = $vram -ge [double] $entry.hardware.preferredVramGB
        $compatible = $ramOk -and ($gpuOk -or
            ($sharedGraphics -and [double] $entry.parametersBillions -le $sharedModelLimit) -or
            (-not $sharedGraphics -and $ram -ge 24))
        $detail = if (-not $ramOk) {
            "RAM insuffisante : $($entry.hardware.minimumRamGB) Go requis"
        }
        elseif ($gpuOk) { 'execution GPU adaptee' }
        elseif ($sharedGraphics) { 'execution CPU/iGPU possible, plus lente' }
        else { 'offload partiel en RAM probable' }
        [pscustomobject]@{
            Id = $entry.id; Tag = $entry.ollamaTag; Variant = $entry.variant
            DownloadGB = $entry.hardware.approximateDownloadGB
            Compatible = $compatible; Detail = $detail
            Rank = [double] $entry.parametersBillions
        }
    }
    $recommended = $choices | Where-Object Compatible | Sort-Object Rank -Descending | Select-Object -First 1
    [pscustomobject]@{
        Choices = @($choices)
        RecommendedId = if ($null -ne $recommended) { $recommended.Id } else { $null }
    }
}

function Save-LocalCodexMachineSelection {
    param([Parameter(Mandatory)][string] $StateDirectory,
        [Parameter(Mandatory)][string] $ModelId, [Parameter(Mandatory)][int] $ContextTokens)
    Assert-LocalCodexAgentContext $ContextTokens
    Write-LocalCodexJson (Join-Path $StateDirectory 'machine.json') ([ordered]@{
        schemaVersion = 1; modelId = $ModelId; contextTokens = $ContextTokens
        updatedAtUtc = [datetime]::UtcNow.ToString('o')
    })
}

function Import-LocalCodexMachineSelection {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory)
    $path = Join-Path $StateDirectory 'machine.json'
    if (Test-Path -LiteralPath $path) {
        $selection = Read-LocalCodexJson $path
        if ($selection.schemaVersion -ne 1) { throw 'Configuration machine Local-Codex non supportee.' }
        Assert-LocalCodexAgentContext ([long] $selection.contextTokens) ([long] $Settings.hermes.minimumContextTokens)
        $Settings.model.id = [string] $selection.modelId
        $Settings.model.contextTokens = [int] $selection.contextTokens
    }
    return $Settings
}

function Invoke-LocalCodexOllama {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $Path, $Body)
    $parameters = @{ Uri = $Settings.ollama.baseUrl.TrimEnd('/') + $Path; TimeoutSec = [int] $Settings.ollama.timeoutSeconds; ErrorAction = 'Stop' }
    if ($null -ne $Body) {
        $parameters.Method = 'Post'
        $parameters.ContentType = 'application/json'
        $parameters.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
    }
    Invoke-RestMethod @parameters
}

function New-LocalCodexModelProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory, [switch] $DownloadModel)
    Assert-LocalCodexAgentContext ([long] $Settings.model.contextTokens) ([long] $Settings.hermes.minimumContextTokens)
    $model = Get-LocalCodexModel $Settings
    $tags = Invoke-LocalCodexOllama $Settings '/api/tags'
    if ($model.ollamaTag -notin @($tags.models.name)) {
        if (-not $DownloadModel) { throw "Modele absent : $($model.ollamaTag). Relancez Install avec -DownloadModel pour autoriser ses $($model.hardware.approximateDownloadGB) Go." }
        if ($PSCmdlet.ShouldProcess($model.ollamaTag, 'Telecharger le modele explicitement demande')) {
            $ollama = (Get-Command ollama.exe -ErrorAction Stop).Source
            Write-Host "      [INFO] Telechargement de $($model.ollamaTag) (~$($model.hardware.approximateDownloadGB) Go)" -ForegroundColor Cyan
            Write-Host '             La progression ci-dessous est fournie directement par Ollama.' -ForegroundColor DarkGray
            & $ollama pull $model.ollamaTag
            if ($LASTEXITCODE -ne 0) { throw "Le telechargement Ollama a echoue (code $LASTEXITCODE)." }
        }
        if ($WhatIfPreference) { return }
    }
    $details = Invoke-LocalCodexOllama $Settings '/api/show' @{ model = $model.ollamaTag }
    if ('tools' -notin @($details.capabilities)) { throw 'Ollama ne confirme pas le tool calling.' }
    if ('thinking' -notin @($details.capabilities)) { throw 'Ollama ne confirme pas le mode de raisonnement.' }
    $contextLimits = @($details.model_info.PSObject.Properties | Where-Object Name -Like '*.context_length' | ForEach-Object { [long] $_.Value })
    if ($contextLimits.Count -eq 0 -or ($contextLimits | Measure-Object -Maximum).Maximum -lt $Settings.model.contextTokens) {
        throw 'Contexte demande non confirme par les metadonnees Ollama.'
    }
    $tags = Invoke-LocalCodexOllama $Settings '/api/tags'
    $base = @($tags.models | Where-Object name -EQ $model.ollamaTag)[0]
    $digest = ([string] $base.digest) -replace '^sha256:', ''
    if ($digest -notmatch '^[a-f0-9]{64}$') { throw 'Digest Ollama invalide.' }
    $profile = "local-codex-$($model.id):$($Settings.model.contextTokens)-$($digest.Substring(0,12))"
    if ($PSCmdlet.ShouldProcess($profile, 'Creer un profil candidat sans remplacer les modeles existants')) {
        if ($profile -notin @($tags.models.name)) {
            $created = Invoke-LocalCodexOllama $Settings '/api/create' @{
                model = $profile; from = $model.ollamaTag; stream = $false
                parameters = @{ num_ctx = [int] $Settings.model.contextTokens }
            }
            if ($created.status -ne 'success') { throw 'Creation du profil Ollama non confirmee.' }
        }
        $profileDetails = Invoke-LocalCodexOllama $Settings '/api/show' @{ model = $profile }
        if ($profileDetails.parameters -notmatch "(?m)^num_ctx\s+$($Settings.model.contextTokens)\s*$") {
            throw 'Profil Ollama existant incompatible ; conserve sans modification.'
        }
        $candidate = [ordered]@{
            schemaVersion = 1; status = 'candidate'; modelId = $model.id; model = $profile
            baseDigest = $base.digest; contextTokens = [int] $Settings.model.contextTokens
            hermesRevision = $Settings.hermes.revision
            createdAtUtc = [datetime]::UtcNow.ToString('o')
        }
        Write-LocalCodexJson (Join-Path $StateDirectory 'candidate.json') $candidate
        Write-Host "      [OK] Profil Ollama pret : $profile" -ForegroundColor Green
        return [pscustomobject] $candidate
    }
}

Export-ModuleMember -Function Get-LocalCodexModel,Get-LocalCodexModelChoices,Save-LocalCodexMachineSelection,Import-LocalCodexMachineSelection,Invoke-LocalCodexOllama,New-LocalCodexModelProfile
