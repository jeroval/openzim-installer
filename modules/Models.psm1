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
    return $model
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
    $model = Get-LocalCodexModel $Settings
    $tags = Invoke-LocalCodexOllama $Settings '/api/tags'
    if ($model.ollamaTag -notin @($tags.models.name)) {
        if (-not $DownloadModel) { throw "Modele absent : $($model.ollamaTag). Relancez Install avec -DownloadModel pour autoriser ses $($model.hardware.approximateDownloadGB) Go." }
        if ($PSCmdlet.ShouldProcess($model.ollamaTag, 'Telecharger le modele explicitement demande')) {
            $ollama = (Get-Command ollama.exe -ErrorAction Stop).Source
            Invoke-LocalCodexProcess $ollama @('pull', $model.ollamaTag) -TimeoutSeconds 7200 | Out-Null
        }
        if ($WhatIfPreference) { return }
    }
    $details = Invoke-LocalCodexOllama $Settings '/api/show' @{ model = $model.ollamaTag }
    if ('tools' -notin @($details.capabilities)) { throw 'Ollama ne confirme pas le tool calling.' }
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
        return [pscustomobject] $candidate
    }
}

Export-ModuleMember -Function Get-LocalCodexModel,Invoke-LocalCodexOllama,New-LocalCodexModelProfile
