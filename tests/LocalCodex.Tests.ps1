$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\LocalCodex.Common.psm1') -Force
Import-Module (Join-Path $root 'modules\Models.psm1') -Force
Import-Module (Join-Path $root 'modules\Hermes.psm1') -Force
Import-Module (Join-Path $root 'modules\Updates.psm1') -Force

Describe 'Promotion et rollback offline' {
    It 'restaure le profil precedent et conserve le stable courant pour retour' {
        $state = Join-Path $TestDrive 'swap'
        $previousHome = Join-Path $state 'previous'
        $config = Join-Path $previousHome 'config.yaml'
        Write-LocalCodexJson $config @{ model='previous' }
        $exe = Join-Path $previousHome 'hermes.exe'
        [IO.File]::WriteAllText($exe, 'fixture')
        $previous = @{ executable=$exe; home=$previousHome; configHash=(Get-FileHash $config).Hash; model='previous' }
        Write-LocalCodexJson (Join-Path $state 'releases.json') @{
            schemaVersion=1; active=@{model='current'}; stable=@{model='current'}
            candidate=$null; previous=$previous
        }
        $result = Restore-LocalCodexRelease $state
        $result.active.model | Should Be 'previous'
        $result.previous.model | Should Be 'current'
        (Get-LocalCodexReleases $state).stable.model | Should Be 'previous'
    }
    It 'refuse un rapport PASS incomplet sans modifier les releases' {
        Mock Get-LocalCodexFingerprint { 'fixture' } -ModuleName Updates
        $state = Join-Path $TestDrive 'incomplete'
        Write-LocalCodexJson (Join-Path $state 'certification.json') @{
            status = 'PASS'; fingerprint = 'fixture'; checks = @(@{ name='Git'; status='PASS' })
        }
        { Publish-LocalCodexCandidate ([pscustomobject]@{}) $state } | Should Throw
        Test-Path (Join-Path $state 'releases.json') | Should Be $false
    }
    It 'refuse le rollback si la configuration precedente a change' {
        $state = Join-Path $TestDrive 'rollback'
        $previousHome = Join-Path $state 'previous'
        $config = Join-Path $previousHome 'config.yaml'
        Write-LocalCodexJson $config @{ model='original' }
        $hash = (Get-FileHash $config).Hash
        $exe = Join-Path $previousHome 'hermes.exe'
        [IO.File]::WriteAllText($exe, 'fixture')
        Write-LocalCodexJson (Join-Path $state 'releases.json') @{
            schemaVersion=1; active=$null; stable=$null; candidate=$null
            previous=@{ executable=$exe; home=$previousHome; configHash=$hash }
        }
        Write-LocalCodexJson $config @{ model='changed' }
        { Restore-LocalCodexRelease $state } | Should Throw
        (Get-LocalCodexReleases $state).active | Should Be $null
    }
}

Describe 'Local-Codex configuration et catalogue offline' {
    It 'transmet les arguments litteraux au processus sans interpretation shell' {
        $script = Join-Path $TestDrive 'argument avec espaces.ps1'
        [IO.File]::WriteAllText($script, 'param([string] $Value) [Console]::Write($Value)')
        $value = 'texte "cite" $(ne_pas_executer) C:\dossier avec espaces\'
        $result = Invoke-LocalCodexProcess (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-File',$script,$value)
        $result.Output | Should Be $value
    }
    It 'importe la configuration Knowledge sans perdre le budget existant' {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $legacy = Read-LocalCodexJson (Join-Path $root 'config\OpenZim.Settings.json')
        $settings.KnowledgeSettings.maxLibrarySizeGB | Should Be $legacy.maxLibrarySizeGB
        (Get-LocalCodexModel $settings).status | Should Be 'candidate'
    }
    It 'refuse latest et un modele deprecated' {
        $catalog = Read-LocalCodexJson (Join-Path $root 'config\ModelCatalog.json')
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $settings.CatalogPath = Join-Path $TestDrive 'catalog.json'
        $catalog.models[0].ollamaTag = 'qwen:latest'
        Write-LocalCodexJson $settings.CatalogPath $catalog
        { Get-LocalCodexModel $settings } | Should Throw
        $catalog.models[0].ollamaTag = 'qwen:9b'
        $catalog.models[0].status = 'deprecated'
        Write-LocalCodexJson $settings.CatalogPath $catalog
        { Get-LocalCodexModel $settings } | Should Throw
    }
    It 'publie et remplace du JSON valide sans laisser de temporaire' {
        $path = Join-Path $TestDrive 'atomic.json'
        Write-LocalCodexJson $path @{ value = 1 }
        Write-LocalCodexJson $path @{ value = 2 }
        (Read-LocalCodexJson $path).value | Should Be 2
        @(Get-ChildItem $TestDrive -Filter '*.tmp').Count | Should Be 0
    }
}

Describe 'Hermes configuration offline' {
    BeforeEach {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $candidate = [pscustomobject]@{ model = 'local-codex:test'; contextTokens = 65536 }
        $server = [pscustomobject]@{ command = 'C:\Python avec espaces\python.exe'; args = @('bridge.py', 'C:\ZIM') }
    }
    It 'configure exclusivement Ollama et preserve les arguments MCP' {
        $config = New-LocalCodexHermesConfiguration $settings $candidate $server
        $config.model.provider | Should Be 'custom'
        $config.model.base_url | Should Be 'http://127.0.0.1:11434/v1'
        $config.model.context_length | Should Be 65536
        $config.mcp_servers.openzim.args[1] | Should Be 'C:\ZIM'
    }
    It 'refuse decraser un fichier Hermes modifie par utilisateur' {
        $state = Join-Path $TestDrive 'state'
        Set-LocalCodexHermesConfiguration $settings $candidate $state $server
        $path = Join-Path (Get-LocalCodexHermesPaths $settings $state).Home 'config.yaml'
        [IO.File]::AppendAllText($path, "`n ")
        { Set-LocalCodexHermesConfiguration $settings $candidate $state $server } | Should Throw
    }
    It 'preserve les autres reglages VS Code et reste idempotent' {
        $workspace = Join-Path $TestDrive 'workspace'
        $path = Join-Path $workspace '.vscode\settings.json'
        Write-LocalCodexJson $path @{ 'editor.fontSize' = 17; 'acp.agents' = @{ Existing = @{ command = 'existing' } } }
        Set-LocalCodexVSCode $settings (Join-Path $TestDrive 'state') $workspace
        Set-LocalCodexVSCode $settings (Join-Path $TestDrive 'state') $workspace
        $result = Read-LocalCodexJson $path
        $result.'editor.fontSize' | Should Be 17
        $result.'acp.agents'.Existing.command | Should Be 'existing'
        $result.'acp.agents'.'Local-Codex'.args[-1] | Should Be (Join-Path $TestDrive 'state')
    }
    It 'ne cree aucun fichier avec WhatIf' {
        $state = Join-Path $TestDrive 'whatif-state'
        Set-LocalCodexHermesConfiguration $settings $candidate $state $server -WhatIf
        Test-Path -LiteralPath $state | Should Be $false
    }
}
