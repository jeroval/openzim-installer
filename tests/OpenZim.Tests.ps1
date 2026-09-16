$projectRoot = Split-Path -Parent $PSScriptRoot
$managerPath = Join-Path $projectRoot 'scripts\Invoke-ZimLibrary.ps1'
$modulePath = Join-Path $projectRoot 'modules\OpenZim.Common.psm1'
$compatibilityServerPath = Join-Path $projectRoot 'scripts\OpenZimCompatServer.py'
$catalogFixture = Join-Path $PSScriptRoot 'fixtures\catalog.xml'
$sourcesFixture = Join-Path $PSScriptRoot 'fixtures\sources.json'

Describe 'Scripts PowerShell' {
    It 'ne contient aucune erreur de syntaxe' {
        $scripts = Get-ChildItem -LiteralPath $projectRoot -Filter '*.ps1' -File -Recurse
        foreach ($script in $scripts) {
            $tokens = $null
            $errors = $null
            [Management.Automation.Language.Parser]::ParseFile(
                $script.FullName,
                [ref] $tokens,
                [ref] $errors
            ) | Out-Null
            if ($errors.Count -gt 0) {
                throw "Erreur de syntaxe dans $($script.Name) : $($errors.Message -join '; ')"
            }
        }
    }

    It 'integre Devstral Small 2 comme modele de code agentique optionnel' {
        $assistant = [IO.File]::ReadAllText((Join-Path $projectRoot 'Start-OpenZimAssistant.ps1'))
        $installer = [IO.File]::ReadAllText((Join-Path $projectRoot 'scripts\Install-LocalAi.ps1'))
        $model = 'devstral-small-2:24b-instruct-2512-q4_K_M'

        if (-not $assistant.Contains('InstallDevstralAgent') -or
            -not $assistant.Contains('recommande pour le code agentique') -or
            -not $assistant.Contains("-Default '3'") -or
            -not $installer.Contains($model)) {
            throw 'Le selecteur Devstral agentique est incomplet.'
        }
    }
}

Describe 'Passerelle MCP pour modeles locaux' {
    It 'expose uniquement des schemas simples a GPT-OSS' {
        $bridge = [IO.File]::ReadAllText($compatibilityServerPath)
        foreach ($toolName in @(
            'openzim_list_archives',
            'openzim_search',
            'openzim_search_archive'
        )) {
            if (-not $bridge.Contains("def $toolName(")) {
                throw "Outil simplifie absent de la passerelle : $toolName"
            }
        }
        if (-not $bridge.Contains('self.backend.mcp.call_tool("zim_query", arguments)')) {
            throw 'La passerelle ne delegue plus au serveur OpenZIM officiel.'
        }
    }
}

Describe 'Manifest des sources' {
    It 'contient des identifiants et priorites uniques' {
        $parsedSources = Get-Content (Join-Path $projectRoot 'config\ZimSources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $sources = @($parsedSources | ForEach-Object { $_ })
        if (@($sources.id | Group-Object | Where-Object Count -GT 1).Count -ne 0) {
            throw 'Le manifest contient des identifiants dupliques.'
        }
        if (@($sources.priority | Group-Object | Where-Object Count -GT 1).Count -ne 0) {
            throw 'Le manifest contient des priorites dupliquees.'
        }
    }

    It 'contient le panier Stack Exchange technique filtre' {
        $parsedSources = Get-Content (Join-Path $projectRoot 'config\ZimSources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $sourceIds = @($parsedSources | ForEach-Object { $_.id })
        $expectedIds = @(
            'code-review', 'computer-science', 'data-science',
            'artificial-intelligence', 'network-engineering',
            'reverse-engineering', 'cryptography', 'electronics'
        )
        foreach ($expectedId in $expectedIds) {
            if ($expectedId -notin $sourceIds) {
                throw "Source technique absente du manifest : $expectedId"
            }
        }
    }
}

Describe 'Selection hors reseau et budget' {
    BeforeEach {
        $library = Join-Path $TestDrive 'library'
        $logDirectory = Join-Path $TestDrive 'logs'
        $configPath = Join-Path $TestDrive 'config.json'
        @{
            libraryRoot = $library
            manifestPath = $sourcesFixture
            catalogUri = 'https://example.invalid/catalog'
            maxLibrarySizeGB = 50
            reserveFreeSpaceGB = 5
            mode = 'simple'
            includeOptional = $false
            preferNoPictures = $true
            verifyChecksum = $true
            logs = @{ directory = $logDirectory; retentionDays = 14 }
            download = @{ retryCount = 2; retryDelaySeconds = 1 }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8

        & $managerPath `
            -Action Plan `
            -ConfigPath $configPath `
            -LibraryRoot $library `
            -ManifestPath $sourcesFixture `
            -CatalogFile $catalogFixture `
            -MaxLibrarySizeGB 50 `
            -Confirm:$false

        $parsedPlan = Get-Content (Join-Path $library 'download-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:plan = @($parsedPlan | ForEach-Object { $_ })
    }

    It 'exclut une archive plus grande que le budget total' {
        if (($plan | Where-Object Source -EQ 'Stack Overflow anglais').Included -ne $false) {
            throw 'Stack Overflow aurait du etre exclu du budget de 50 Go.'
        }
    }

    It 'conserve une petite archive prioritaire admissible' {
        if (($plan | Where-Object Source -EQ 'Python PEP').Included -ne $true) {
            throw 'Python PEP aurait du etre inclus.'
        }
    }

    It 'selectionne la version la plus recente' {
        if (($plan | Where-Object Source -EQ 'Python PEP').FileName -ne 'peps.python_en_all_2024-05.zim') {
            throw 'La version Python PEP la plus recente n a pas ete selectionnee.'
        }
    }

    It 'choisit une variante Wikipedia compacte avec 50 Go' {
        if (@($plan | Where-Object FileName -EQ 'wikipedia_en_top_nopic_2026-06.zim').Count -ne 1) {
            throw 'La variante Wikipedia top aurait du etre choisie avec 50 Go.'
        }
        if (@($plan | Where-Object FileName -EQ 'wikipedia_en_all_nopic_2026-06.zim').Count -ne 0) {
            throw 'La variante Wikipedia complete ne doit pas apparaitre dans le profil 50 Go.'
        }
    }

    It 'enrichit automatiquement le panier avec 100 Go' {
        $largerLibrary = Join-Path $TestDrive 'library-100'
        & $managerPath `
            -Action Plan `
            -ConfigPath $configPath `
            -LibraryRoot $largerLibrary `
            -ManifestPath $sourcesFixture `
            -CatalogFile $catalogFixture `
            -MaxLibrarySizeGB 100 `
            -Confirm:$false

        $largerPlan = @(Get-Content (Join-Path $largerLibrary 'download-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
        if (@($largerPlan | Where-Object FileName -EQ 'wikipedia_en_all_nopic_2026-06.zim').Count -ne 1) {
            throw 'La variante Wikipedia complete aurait du etre choisie avec 100 Go.'
        }
        if (($largerPlan | Where-Object Source -EQ 'Stack Overflow anglais').Included -ne $false) {
            throw 'Stack Overflow depasse encore le plafond de 100 Go une fois le panier construit.'
        }
    }

    It 'ajoute Stack Overflow complet avec 200 Go' {
        $largestLibrary = Join-Path $TestDrive 'library-200'
        & $managerPath `
            -Action Plan `
            -ConfigPath $configPath `
            -LibraryRoot $largestLibrary `
            -ManifestPath $sourcesFixture `
            -CatalogFile $catalogFixture `
            -MaxLibrarySizeGB 200 `
            -Confirm:$false

        $largestPlan = @(Get-Content (Join-Path $largestLibrary 'download-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
        if (($largestPlan | Where-Object Source -EQ 'Stack Overflow anglais').Included -ne $true) {
            throw 'Stack Overflow aurait du etre ajoute au profil 200 Go.'
        }
    }
}

Describe 'Personnalisation centree sur l usage' {
    It 'priorise la categorie correspondant au profil lorsque le budget impose un choix' {
        $profileRoot = Join-Path $TestDrive 'profile-library'
        $profileManifest = Join-Path $TestDrive 'profile-sources.json'
        $profileCatalog = Join-Path $TestDrive 'profile-catalog.xml'
        $profileConfig = Join-Path $TestDrive 'profile-config.json'

        @(
            @{ id = 'systems-doc'; title = 'Documentation systemes'; category = 'Systems'; pattern = '^systems_en_all_2026-01\.zim$'; required = $true; priority = 1; relevance = 50 },
            @{ id = 'web-doc'; title = 'Documentation Web'; category = 'Web'; pattern = '^web_en_all_2026-01\.zim$'; required = $true; priority = 2; relevance = 50 }
        ) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $profileManifest -Encoding UTF8

        @'
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><title>Systemes</title><updated>2026-01-01T00:00:00Z</updated><link rel="http://opds-spec.org/acquisition/open-access" type="application/x-zim" href="https://example.invalid/systems_en_all_2026-01.zim.meta4" length="751619276" /></entry>
  <entry><title>Web</title><updated>2026-01-01T00:00:00Z</updated><link rel="http://opds-spec.org/acquisition/open-access" type="application/x-zim" href="https://example.invalid/web_en_all_2026-01.zim.meta4" length="751619276" /></entry>
</feed>
'@ | Set-Content -LiteralPath $profileCatalog -Encoding UTF8

        @{
            libraryRoot = $profileRoot
            manifestPath = $profileManifest
            catalogUri = 'https://example.invalid/catalog'
            maxLibrarySizeGB = 1
            reserveFreeSpaceGB = 0
            mode = 'simple'
            includeOptional = $false
            preferNoPictures = $true
            verifyChecksum = $true
            logs = @{ directory = (Join-Path $TestDrive 'profile-logs'); retentionDays = 1 }
            download = @{ retryCount = 1; retryDelaySeconds = 1 }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $profileConfig -Encoding UTF8

        & $managerPath -Action Plan -ConfigPath $profileConfig -CatalogFile $profileCatalog `
            -ManifestPath $profileManifest -LibraryRoot $profileRoot -MaxLibrarySizeGB 1 `
            -UsageProfile web -Confirm:$false

        $profilePlan = @(Get-Content (Join-Path $profileRoot 'download-plan.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json | ForEach-Object { $_ })
        if (($profilePlan | Where-Object Source -EQ 'Documentation Web').Included -ne $true) {
            throw 'Le profil Web aurait du inclure la documentation Web en premier.'
        }
        if (($profilePlan | Where-Object Source -EQ 'Documentation systemes').Included -ne $false) {
            throw 'La documentation systemes aurait du etre exclue faute de place.'
        }
        if (($profilePlan | Where-Object Source -EQ 'Documentation Web').Affinite -le 0) {
            throw "Le bonus d'affinite Web n'apparait pas dans le plan."
        }
    }
}

Describe 'Journalisation structuree' {
    It 'ecrit une ligne JSON exploitable' {
        Import-Module $modulePath -Force
        $logPath = Initialize-OpenZimLog -Directory (Join-Path $TestDrive 'logs') -RetentionDays 14 -Prefix 'test'
        Write-OpenZimLog -Level INFO -Event 'unit_test' -Message 'message de test' -Data @{ value = 42 }
        $record = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($record.level -ne 'INFO' -or $record.event -ne 'unit_test' -or $record.data.value -ne 42) {
            throw 'La ligne de journal JSON ne correspond pas aux valeurs attendues.'
        }
    }
}

Describe 'Instructions IA du projet' {
    BeforeEach {
        Import-Module $modulePath -Force
        $script:workspace = Join-Path $TestDrive 'workspace'
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    }

    It 'preserve les instructions existantes et reste idempotent' {
        $githubDirectory = Join-Path $workspace '.github'
        New-Item -ItemType Directory -Path $githubDirectory -Force | Out-Null
        $instructionsPath = Join-Path $githubDirectory 'copilot-instructions.md'
        [IO.File]::WriteAllText($instructionsPath, "# Regles du projet`r`n", [Text.UTF8Encoding]::new($false))
        $gitIgnorePath = Join-Path $workspace '.gitignore'
        [IO.File]::WriteAllText($gitIgnorePath, "# Regles existantes`r`n.env`r`n", [Text.UTF8Encoding]::new($false))

        Set-OpenZimProjectInstructions -WorkspacePath $workspace -Confirm:$false | Out-Null
        Set-OpenZimProjectInstructions -WorkspacePath $workspace -Confirm:$false | Out-Null

        $content = [IO.File]::ReadAllText($instructionsPath)
        if (-not $content.Contains('# Regles du projet')) {
            throw 'Les instructions existantes ont ete supprimees.'
        }
        if ([regex]::Matches($content, '<!-- openzim-mcp:begin -->').Count -ne 1) {
            throw 'Le bloc OpenZIM a ete duplique.'
        }
        if (-not $content.Contains('openzim_list_archives')) {
            throw "L'instruction d'utiliser la passerelle OpenZIM est absente."
        }

        $standardsPath = Join-Path $workspace '.github\instructions\openzim-development-standards.instructions.md'
        $startupPromptPath = Join-Path $workspace '.github\prompts\verifier-openzim.prompt.md'
        $guidePath = Join-Path $workspace 'docs\ai\Guide-Bonnes-Pratiques-Code.md'
        $agentsPath = Join-Path $workspace 'AGENTS.md'
        foreach ($generatedPath in @($standardsPath, $startupPromptPath, $guidePath, $agentsPath)) {
            if (-not (Test-Path -LiteralPath $generatedPath -PathType Leaf)) {
                throw "Fichier de standards absent : $generatedPath"
            }
        }
        $standards = [IO.File]::ReadAllText($standardsPath)
        if ($standards -notmatch 'applyTo:\s*[''\"]\*\*[''\"]' -or
            [regex]::Matches($standards, '<!-- openzim-standards:begin -->').Count -ne 1) {
            throw 'Le fichier de standards IA est invalide ou duplique.'
        }
        if (-not ([IO.File]::ReadAllText($agentsPath)).Contains('<!-- openzim-agent-policy:begin -->')) {
            throw 'La politique AGENTS.md geree est absente.'
        }
        $startupPrompt = [IO.File]::ReadAllText($startupPromptPath)
        if ($startupPrompt -notmatch 'name:\s*[''"]verifier-openzim[''"]' -or
            -not $startupPrompt.Contains('openzim_list_archives') -or
            -not $startupPrompt.Contains('openzim_search_archive') -or
            -not $startupPrompt.Contains('exclusivement en fran')) {
            throw 'Le prompt de verification OpenZIM est incomplet.'
        }

        $gitIgnore = [IO.File]::ReadAllText($gitIgnorePath)
        if (-not $gitIgnore.Contains('.env') -or
            -not $gitIgnore.Contains('.vscode/mcp.json') -or
            -not $gitIgnore.Contains('.github/copilot-instructions.md') -or
            -not $gitIgnore.Contains('debug.log') -or
            -not $gitIgnore.Contains('*.zim') -or
            -not $gitIgnore.Contains('zim-inventory.json')) {
            throw 'Les regles Git existantes ou locales OpenZIM sont absentes.'
        }
        if ([regex]::Matches($gitIgnore, '# openzim-local:begin').Count -ne 1) {
            throw 'Le bloc Git local OpenZIM a ete duplique.'
        }
    }

    It 'refuse un marqueur incomplet sans modifier le fichier' {
        $githubDirectory = Join-Path $workspace '.github'
        New-Item -ItemType Directory -Path $githubDirectory -Force | Out-Null
        $instructionsPath = Join-Path $githubDirectory 'copilot-instructions.md'
        $original = '<!-- openzim-mcp:begin -->'
        [IO.File]::WriteAllText($instructionsPath, $original, [Text.UTF8Encoding]::new($false))

        $rejected = $false
        try {
            Set-OpenZimProjectInstructions -WorkspacePath $workspace -Confirm:$false | Out-Null
        }
        catch {
            $rejected = $true
        }
        if (-not $rejected) {
            throw 'Le generateur aurait du refuser le marqueur incomplet.'
        }
        if ([IO.File]::ReadAllText($instructionsPath) -ne $original) {
            throw 'Le fichier avec un marqueur incomplet a ete modifie.'
        }
    }
}

Describe 'Premier lancement' {
    It 'affiche correctement une bibliotheque vide' {
        $emptyLibrary = Join-Path $TestDrive 'empty-library'
        New-Item -ItemType Directory -Path $emptyLibrary -Force | Out-Null
        $statusOutput = & $managerPath `
            -Action Status `
            -ConfigPath (Join-Path $projectRoot 'config\OpenZim.Settings.json') `
            -LibraryRoot $emptyLibrary 6>&1 | Out-String

        if ($statusOutput -notmatch '0 archive\(s\)') {
            throw "Le statut vide est inattendu : $statusOutput"
        }
    }
}
