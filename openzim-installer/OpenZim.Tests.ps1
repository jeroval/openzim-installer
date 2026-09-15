$projectRoot = Split-Path -Parent $PSScriptRoot
$managerPath = Join-Path $projectRoot 'manage-zim-library.ps1'
$modulePath = Join-Path $projectRoot 'OpenZim.Common.psm1'
$catalogFixture = Join-Path $PSScriptRoot 'fixtures\catalog.xml'
$sourcesFixture = Join-Path $PSScriptRoot 'fixtures\sources.json'

Describe 'Scripts PowerShell' {
    It 'ne contient aucune erreur de syntaxe' {
        $scripts = Get-ChildItem -LiteralPath $projectRoot -Filter '*.ps1' -File
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
}

Describe 'Manifest des sources' {
    It 'contient des identifiants et priorites uniques' {
        $parsedSources = Get-Content (Join-Path $projectRoot 'zim-sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $sources = @($parsedSources | ForEach-Object { $_ })
        if (@($sources.id | Group-Object | Where-Object Count -GT 1).Count -ne 0) {
            throw 'Le manifest contient des identifiants dupliques.'
        }
        if (@($sources.priority | Group-Object | Where-Object Count -GT 1).Count -ne 0) {
            throw 'Le manifest contient des priorites dupliquees.'
        }
    }

    It 'contient le panier Stack Exchange technique filtre' {
        $parsedSources = Get-Content (Join-Path $projectRoot 'zim-sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
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

Describe 'Premier lancement' {
    It 'affiche correctement une bibliotheque vide' {
        $emptyLibrary = Join-Path $TestDrive 'empty-library'
        New-Item -ItemType Directory -Path $emptyLibrary -Force | Out-Null
        $statusOutput = & $managerPath `
            -Action Status `
            -ConfigPath (Join-Path $projectRoot 'openzim.config.json') `
            -LibraryRoot $emptyLibrary 6>&1 | Out-String

        if ($statusOutput -notmatch '0 archive\(s\)') {
            throw "Le statut vide est inattendu : $statusOutput"
        }
    }
}
