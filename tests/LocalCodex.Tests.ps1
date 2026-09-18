$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\LocalCodex.Common.psm1') -Force
Import-Module (Join-Path $root 'modules\Models.psm1') -Force
Import-Module (Join-Path $root 'modules\Hermes.psm1') -Force
Import-Module (Join-Path $root 'modules\Updates.psm1') -Force
Import-Module (Join-Path $root 'modules\UserExperience.psm1') -Force
Import-Module (Join-Path $root 'modules\Project.psm1') -Force
Import-Module (Join-Path $root 'modules\Prerequisites.psm1') -Force
Import-Module (Join-Path $root 'modules\Doctor.psm1') -Force
Import-Module (Join-Path $root 'modules\Certification.psm1') -Force

Describe 'Promotion et rollback offline' {
    It 'actualise l empreinte du candidat actif apres reconfiguration' {
        Mock Get-LocalCodexHermesPaths {
            [pscustomobject]@{ Home = Join-Path $TestDrive 'active-candidate'; Executable = Join-Path $TestDrive 'hermes.exe' }
        } -ModuleName Updates
        $state = Join-Path $TestDrive 'candidate-refresh'
        $profileDirectory = Join-Path $TestDrive 'active-candidate'
        [IO.Directory]::CreateDirectory($profileDirectory) | Out-Null
        Write-LocalCodexJson (Join-Path $profileDirectory 'config.yaml') @{ value = 'new' }
        Write-LocalCodexJson (Join-Path $state 'candidate.json') @{
            model='model'; contextTokens=65536; baseDigest=('a' * 64)
        }
        Write-LocalCodexJson (Join-Path $state 'releases.json') @{
            schemaVersion=1; stable=$null; previous=$null
            active=@{ status='candidate'; home=$profileDirectory; configHash='OLD' }
            candidate=@{ status='candidate'; home=$profileDirectory; configHash='OLD' }
        }
        $settings = [pscustomobject]@{ hermes = [pscustomobject]@{ revision = 'a' * 40 } }
        $result = Set-LocalCodexCandidateRelease $settings $state
        $result.active.configHash | Should Be (Get-FileHash (Join-Path $profileDirectory 'config.yaml')).Hash
    }
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
    It 'centralise chaque prerequis machine dans une definition unique' {
        $definitions = @(Get-LocalCodexPrerequisiteDefinitions)
        $definitions.Count | Should Be 4
        @($definitions.PackageId | Select-Object -Unique).Count | Should Be $definitions.Count
        @($definitions | Where-Object { @($_.Commands).Count -eq 0 }).Count | Should Be 0
        @($definitions | Where-Object Name -Like 'Python*').Count | Should Be 0
    }

    It 'recommande un seul Qwen selon le materiel detecte' {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $gpu = [pscustomobject]@{ ramTotalGB = 32; vramGB = 12; vramReliable = $true }
        (Get-LocalCodexModelChoices $settings $gpu).RecommendedId | Should Be 'qwen35-9b-q4'
        $igpu = [pscustomobject]@{ ramTotalGB = 16; vramGB = 0.5; vramReliable = $false }
        (Get-LocalCodexModelChoices $settings $igpu).RecommendedId | Should Be 'qwen35-4b'
    }

    It 'persiste et recharge le choix machine' {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $state = Join-Path $TestDrive 'machine-state'
        Save-LocalCodexMachineSelection $state 'qwen35-2b' 65536
        $loaded = Import-LocalCodexMachineSelection $settings $state
        $loaded.model.id | Should Be 'qwen35-2b'
        $loaded.model.contextTokens | Should Be 65536
    }

    It 'refuse de sacrifier le minimum Hermes pour economiser la VRAM' {
        $state = Join-Path $TestDrive 'machine-32k'
        { Save-LocalCodexMachineSelection $state 'qwen35-4b' 32768 } | Should Throw
        Test-Path -LiteralPath (Join-Path $state 'machine.json') | Should Be $false
    }

    It 'rend ACP obligatoire dans la configuration produit' {
        $configDirectory = Join-Path $TestDrive 'invalid-integration'
        [IO.Directory]::CreateDirectory($configDirectory) | Out-Null
        Copy-Item (Join-Path $root 'config\ModelCatalog.json') $configDirectory
        Copy-Item (Join-Path $root 'config\Knowledge.Settings.json') $configDirectory
        $configuration = Read-LocalCodexJson (Join-Path $root 'config\LocalCodex.Settings.json')
        $configuration.integration.protocol = 'CHAT'
        $path = Join-Path $configDirectory 'LocalCodex.Settings.json'
        Write-LocalCodexJson $path $configuration
        { Get-LocalCodexConfiguration $path } | Should Throw
    }

    It 'ne propose que les variantes Qwen 3.5 jusqu a 9B' {
        $catalog = Read-LocalCodexJson (Join-Path $root 'config\ModelCatalog.json')
        $tags = @($catalog.models | ForEach-Object ollamaTag)
        foreach ($tag in @('qwen3.5:0.8b', 'qwen3.5:2b', 'qwen3.5:4b', 'qwen3.5:9b-q4_K_M')) {
            if ($tag -notin $tags) { throw "Tag Qwen 3.5 absent : $tag" }
        }
        if (@($catalog.models | Where-Object { $_.parametersBillions -gt 9.65 }).Count -ne 0) {
            throw 'Le catalogue Local-Codex ne doit pas proposer de modele superieur a 9B.'
        }
        if (@($catalog.models | Where-Object { -not $_.capabilities.tools -or -not $_.capabilities.thinking }).Count -ne 0) {
            throw 'Chaque modele propose doit prendre en charge les outils et le raisonnement.'
        }
    }

    It 'transmet les arguments litteraux au processus sans interpretation shell' {
        $script = Join-Path $TestDrive 'argument avec espaces.ps1'
        [IO.File]::WriteAllText($script, 'param([string] $Value) [Console]::Write($Value)')
        $value = 'texte "cite" $(ne_pas_executer) C:\dossier avec espaces\'
        $result = Invoke-LocalCodexProcess (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-File',$script,$value)
        $result.Output | Should Be $value
    }
    It 'importe la configuration Knowledge sans perdre le budget existant' {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $knowledge = Read-LocalCodexJson (Join-Path $root 'config\Knowledge.Settings.json')
        $settings.KnowledgeSettings.maxLibrarySizeGB | Should Be $knowledge.maxLibrarySizeGB
        (Get-LocalCodexModel $settings).status | Should Be 'candidate'
    }
    It 'refuse latest et un modele deprecated' {
        $catalog = Read-LocalCodexJson (Join-Path $root 'config\ModelCatalog.json')
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $settings.CatalogPath = Join-Path $TestDrive 'catalog.json'
        $configuredModel = @($catalog.models | Where-Object id -EQ $settings.model.id)[0]
        $configuredModel.ollamaTag = 'qwen:latest'
        Write-LocalCodexJson $settings.CatalogPath $catalog
        { Get-LocalCodexModel $settings } | Should Throw
        $configuredModel.ollamaTag = 'qwen:9b'
        $configuredModel.status = 'deprecated'
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
        $config.agent.api_max_retries | Should Be 5
        $config.agent.empty_response_guard.enabled | Should Be $true
        $config.agent.empty_response_guard.cost_threshold_usd | Should Be 0.25
    }
    It 'refuse une politique de retry non bornee' {
        $configDirectory = Join-Path $TestDrive 'invalid-retry'
        [IO.Directory]::CreateDirectory($configDirectory) | Out-Null
        Copy-Item (Join-Path $root 'config\ModelCatalog.json') $configDirectory
        Copy-Item (Join-Path $root 'config\Knowledge.Settings.json') $configDirectory
        $configuration = Read-LocalCodexJson (Join-Path $root 'config\LocalCodex.Settings.json')
        $configuration.hermes.apiMaxRetries = 50
        $path = Join-Path $configDirectory 'LocalCodex.Settings.json'
        Write-LocalCodexJson $path $configuration
        { Get-LocalCodexConfiguration $path } | Should Throw
    }
    It 'applique les retries sur une ancienne configuration schema 1' {
        $configDirectory = Join-Path $TestDrive 'legacy-retry'
        [IO.Directory]::CreateDirectory($configDirectory) | Out-Null
        Copy-Item (Join-Path $root 'config\ModelCatalog.json') $configDirectory
        Copy-Item (Join-Path $root 'config\Knowledge.Settings.json') $configDirectory
        $configuration = Read-LocalCodexJson (Join-Path $root 'config\LocalCodex.Settings.json')
        $configuration.hermes.PSObject.Properties.Remove('apiMaxRetries')
        $configuration.hermes.PSObject.Properties.Remove('emptyResponseGuard')
        $path = Join-Path $configDirectory 'LocalCodex.Settings.json'
        Write-LocalCodexJson $path $configuration
        $migrated = Get-LocalCodexConfiguration $path
        $migrated.hermes.apiMaxRetries | Should Be 5
        $migrated.hermes.emptyResponseGuard | Should Be $true
    }
    It 'refuse un candidat Hermes sous 64K' {
        $candidate.contextTokens = 32768
        { New-LocalCodexHermesConfiguration $settings $candidate $server } | Should Throw
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
        ($result.'acp.agents'.'Local-Codex'.args -join ' ') | Should Match 'Start-LocalCodexAcp\.ps1'
    }
    It 'ne cree aucun fichier avec WhatIf' {
        $state = Join-Path $TestDrive 'whatif-state'
        Set-LocalCodexHermesConfiguration $settings $candidate $state $server -WhatIf
        Test-Path -LiteralPath $state | Should Be $false
    }
}

Describe 'Experience utilisateur Local-Codex' {
    It 'annonce READY uniquement lorsque toutes les preuves sont PASS' {
        $report = [pscustomobject]@{ checks = @(
            [pscustomobject]@{ name = 'Git'; status = 'PASS'; detail = 'git' }
            [pscustomobject]@{ name = 'ACP'; status = 'PASS'; detail = 'acp' }
            [pscustomobject]@{ name = 'Agent.retest'; status = 'PASS'; detail = 'tests' }
            [pscustomobject]@{ name = 'OpenZimMCP'; status = 'PASS'; detail = 'zim' }
        ) }
        $view = Get-LocalCodexVerificationView $report
        $view.Ready | Should Be $true
        @($view.Rows | Where-Object Group -EQ 'AGENT').Count | Should Be 1
    }

    It 'ne masque ni un echec ni une verification non executee' {
        $report = [pscustomobject]@{ checks = @(
            [pscustomobject]@{ name = 'Git'; status = 'PASS'; detail = '' }
            [pscustomobject]@{ name = 'ACP'; status = 'FAIL'; detail = 'absent' }
            [pscustomobject]@{ name = 'AgentScenario'; status = 'NOT_RUN'; detail = 'prerequis' }
        ) }
        $view = Get-LocalCodexVerificationView $report
        $view.Ready | Should Be $false
        $view.ErrorCount | Should Be 1
        $view.PendingCount | Should Be 1
        @($view.Rows | Where-Object Name -EQ 'ACP')[0].Purpose | Should Match 'Visual Studio Code'
    }

    It 'accepte le dossier .vscode et retrouve la racine du projet' {
        $project = Join-Path $TestDrive 'project-root'
        [IO.Directory]::CreateDirectory((Join-Path $project '.vscode')) | Out-Null
        Resolve-LocalCodexProjectRoot (Join-Path $project '.vscode') | Should Be $project
    }

    It 'deploie la commande verifier-codex et son diagnostic dans un projet' {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $project = Join-Path $TestDrive 'command-project'
        [IO.Directory]::CreateDirectory($project) | Out-Null
        Set-LocalCodexProjectAgentConfiguration $settings (Join-Path $TestDrive 'command-state') $project -Confirm:$false | Out-Null
        $prompt = Join-Path $project '.github\prompts\verifier-codex.prompt.md'
        $health = Join-Path $project '.local-codex\Test-LocalCodexHealth.ps1'
        $nativeAgent = Join-Path $project '.github\agents\local-codex-native.agent.md'
        $nativeMcp = Join-Path $project '.vscode\mcp.json'
        $agents = Join-Path $project 'AGENTS.md'
        Test-Path -LiteralPath $prompt -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $health -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $nativeAgent -PathType Leaf | Should Be $true
        Test-Path -LiteralPath $nativeMcp -PathType Leaf | Should Be $true
        ([IO.File]::ReadAllText($nativeAgent)).Contains('## Dialogue adaptatif et initiative') | Should Be $true
        ([IO.File]::ReadAllText($agents)).Contains('au maximum trois questions') | Should Be $true
        $promptContent = [IO.File]::ReadAllText($prompt)
        $healthContent = [IO.File]::ReadAllText($health)
        $promptContent.Contains("name: 'verifier-codex'") | Should Be $true
        $promptContent.Contains("'execute/runInTerminal'") | Should Be $true
        $promptContent.Contains('openzim_search_archive') | Should Be $true
        $healthContent.Contains("Add-HealthCheck 'AutomaticRetry'") | Should Be $true
        $healthContent.Contains("Add-HealthCheck 'NativeChat'") | Should Be $true
        (Read-LocalCodexJson $nativeMcp).servers.openzim.type | Should Be 'stdio'
        Test-Path -LiteralPath (Join-Path $project '.github\prompts\verifier-openzim.prompt.md') | Should Be $false
    }

    It 'preserve les autres serveurs MCP du chat natif' {
        $project = Join-Path $TestDrive 'native-mcp-project'
        $path = Join-Path $project '.vscode\mcp.json'
        Write-LocalCodexJson $path @{ servers = @{ existing = @{ type='http'; url='http://127.0.0.1:9999' } } }
        $server = [pscustomobject]@{ command='C:\Tools\python.exe'; args=@('bridge.py','C:\ZIM') }
        Set-LocalCodexNativeMcp $project $server -Confirm:$false
        $result = Read-LocalCodexJson $path
        $result.servers.existing.url | Should Be 'http://127.0.0.1:9999'
        $result.servers.openzim.command | Should Be 'C:\Tools\python.exe'
    }

    It 'refuse d ecraser un serveur OpenZIM natif personnalise' {
        $project = Join-Path $TestDrive 'native-mcp-conflict'
        $path = Join-Path $project '.vscode\mcp.json'
        Write-LocalCodexJson $path @{ servers = @{ openzim = @{ type='stdio'; command='custom.exe'; args=@('custom') } } }
        $server = [pscustomobject]@{ command='C:\Tools\python.exe'; args=@('bridge.py','C:\ZIM') }
        { Set-LocalCodexNativeMcp $project $server -Confirm:$false } | Should Throw
        (Read-LocalCodexJson $path).servers.openzim.command | Should Be 'custom.exe'
    }

    It 'inventorie les emplacements importants sans modifier la machine' {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        $items = @(Get-LocalCodexComponentInventory $settings (Join-Path $TestDrive 'health-state'))
        foreach ($name in @('Hermes Agent', 'OpenZIM MCP', 'Bibliotheque ZIM', 'Modeles Ollama', 'Etat Local-Codex')) {
            @($items | Where-Object Name -EQ $name).Count | Should Be 1
        }
    }

    It 'explique chaque preuve agentique au lieu d afficher seulement un chemin' {
        Get-LocalCodexAgentEvidenceLabel 'terminal' | Should Match 'commandes de test'
        Get-LocalCodexAgentEvidenceLabel 'multiFileEdit' | Should Match 'deux fichiers'
    }

    It 'expose la gestion complete de la tache ZIM dans le produit unifie' {
        $knowledgeModule = Get-Content -LiteralPath (Join-Path $root 'modules\Knowledge.psm1') -Raw -Encoding UTF8
        foreach ($action in @('-Action Status', '-Action Create', '-Action Run', '-Action Remove')) {
            $knowledgeModule | Should Match ([regex]::Escape($action))
        }
    }

    It 'refuse de configurer implicitement le dossier courant comme projet' {
        $settings = Get-LocalCodexConfiguration (Join-Path $root 'config\LocalCodex.Settings.json')
        { Set-LocalCodexProjectAgentConfiguration $settings (Join-Path $TestDrive 'state') '' } | Should Throw
    }

    It 'charge explicitement le mutex et le journal pour les actions avec ecriture' {
        $state = Join-Path $TestDrive 'uninstall-state'
        { & (Join-Path $root 'Local-Codex.ps1') -Action Uninstall `
                -StateDirectory $state -Confirm:$false } | Should Not Throw
        Test-Path -LiteralPath (Join-Path $state 'releases.json') | Should Be $true
    }
}
