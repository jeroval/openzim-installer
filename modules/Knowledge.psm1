#requires -Version 5.1

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LocalCodex.Common.psm1')

function Set-LocalCodexKnowledgeBudget {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] [ValidateRange(1, 4096)] [int] $BudgetGB
    )

    $configPath = [string] $Settings.KnowledgeConfigPath
    $configuration = Read-LocalCodexJson $configPath
    $previousBudgetGB = [int] $configuration.maxLibrarySizeGB
    if ($previousBudgetGB -eq $BudgetGB) {
        $Settings.KnowledgeSettings.maxLibrarySizeGB = $BudgetGB
        return [pscustomobject]@{ PreviousBudgetGB = $previousBudgetGB; BudgetGB = $BudgetGB; Changed = $false }
    }

    $configuration.maxLibrarySizeGB = $BudgetGB
    if ($PSCmdlet.ShouldProcess($configPath, "Definir le quota ZIM a $BudgetGB Go")) {
        Write-LocalCodexJson $configPath $configuration
        $Settings.KnowledgeSettings.maxLibrarySizeGB = $BudgetGB
    }
    return [pscustomobject]@{ PreviousBudgetGB = $previousBudgetGB; BudgetGB = $BudgetGB; Changed = $true }
}

function Read-LocalCodexKnowledgeBudget {
    param([Parameter(Mandatory)] [int] $CurrentBudgetGB)

    do {
        Write-Host "`nQUOTA DE LA BIBLIOTHEQUE ZIM" -ForegroundColor Cyan
        Write-Host "Quota actuel : $CurrentBudgetGB Go" -ForegroundColor DarkGray
        Write-Host 'Le quota limite le panier selectionne. Il ne supprime aucune archive deja installee.' -ForegroundColor DarkGray
        Write-Host '1. 50 Go  - documentation technique compacte'
        Write-Host '2. 100 Go - documentation technique et sources complementaires'
        Write-Host '3. 200 Go - panier etendu, avec Stack Overflow complet si disponible'
        Write-Host '4. Autre valeur entre 1 et 4096 Go'
        Write-Host 'Q. Annuler'
        $choice = (Read-Host 'Choix').Trim().ToUpperInvariant()
        switch ($choice) {
            '1' { return 50 }
            '2' { return 100 }
            '3' { return 200 }
            '4' {
                $value = 0
                $text = (Read-Host 'Quota maximum en Go').Trim()
                if ([int]::TryParse($text, [ref] $value) -and $value -ge 1 -and $value -le 4096) {
                    return $value
                }
                Write-Warning 'Saisissez un nombre entier compris entre 1 et 4096.'
            }
            'Q' { return $null }
            default { Write-Warning 'Choix invalide.' }
        }
    } while ($true)
}

function Start-LocalCodexKnowledge {
    param([Parameter(Mandatory)] $Settings)

    $root = Split-Path -Parent $PSScriptRoot
    $manager = Join-Path $root 'scripts\Invoke-ZimLibrary.ps1'
    $installer = Join-Path $root 'scripts\Install-OpenZimMcp.ps1'
    $scheduler = Join-Path $root 'scripts\Invoke-ZimScheduledTask.ps1'
    do {
        Write-Host "`nDOCUMENTATION LOCALE`n"
        Write-Host "Quota actuel : $($Settings.KnowledgeSettings.maxLibrarySizeGB) Go" -ForegroundColor DarkGray
        Write-Host '1. Definir le quota et recalculer le plan'
        Write-Host '2. Installer ou reparer OpenZIM MCP'
        Write-Host '3. Voir le plan de telechargement'
        Write-Host '4. Telecharger les archives selectionnees'
        Write-Host '5. Rechercher et installer les mises a jour'
        Write-Host '6. Afficher les archives installees'
        Write-Host '7. Gerer la mise a jour hebdomadaire'
        Write-Host 'Q. Retour'
        $choice = (Read-Host 'Choix').Trim().ToUpperInvariant()
        switch ($choice) {
            '1' {
                $budgetGB = Read-LocalCodexKnowledgeBudget ([int] $Settings.KnowledgeSettings.maxLibrarySizeGB)
                if ($null -ne $budgetGB) {
                    $result = Set-LocalCodexKnowledgeBudget $Settings $budgetGB -Confirm:$false
                    $change = if ($result.Changed) { "$($result.PreviousBudgetGB) -> $($result.BudgetGB) Go" } else { "$($result.BudgetGB) Go (inchange)" }
                    Write-Host "[OK] Quota enregistre : $change" -ForegroundColor Green
                    Write-Host '[INFO] Recalcul du panier uniquement ; aucun fichier volumineux ne sera telecharge.' -ForegroundColor Cyan
                    & $manager -Action Plan -ConfigPath $Settings.KnowledgeConfigPath
                }
            }
            '2' { & $installer -Version $Settings.openzim.version }
            '3' { & $manager -Action Plan -ConfigPath $Settings.KnowledgeConfigPath }
            '4' { & $manager -Action Download -ConfigPath $Settings.KnowledgeConfigPath }
            '5' { & $manager -Action Update -ConfigPath $Settings.KnowledgeConfigPath }
            '6' { & $manager -Action Status -ConfigPath $Settings.KnowledgeConfigPath }
            '7' {
                do {
                    Write-Host "`nMISE A JOUR HEBDOMADAIRE`n"
                    Write-Host '1. Verifier si la tache existe et voir son dernier resultat'
                    Write-Host '2. Creer ou actualiser la tache (dimanche a 03:00)'
                    Write-Host '3. Lancer la tache maintenant pour la tester'
                    Write-Host '4. Supprimer la tache (les archives sont conservees)'
                    Write-Host 'Q. Retour'
                    $scheduleChoice = (Read-Host 'Choix').Trim().ToUpperInvariant()
                    switch ($scheduleChoice) {
                        '1' { & $scheduler -Action Status -ConfigPath $Settings.KnowledgeConfigPath }
                        '2' {
                            & $scheduler -Action Create -ConfigPath $Settings.KnowledgeConfigPath `
                                -LibraryRoot $Settings.KnowledgeSettings.libraryRoot
                        }
                        '3' {
                            $answer = Read-Host 'Cette operation peut telecharger des archives. Lancer maintenant ? [o/N]'
                            if ($answer -match '^(?i:o|oui|y|yes)$') {
                                & $scheduler -Action Run -ConfigPath $Settings.KnowledgeConfigPath
                            }
                            else { Write-Host '[INFO] Test annule.' }
                        }
                        '4' {
                            $answer = Read-Host 'Supprimer uniquement la tache planifiee ? [o/N]'
                            if ($answer -match '^(?i:o|oui|y|yes)$') {
                                & $scheduler -Action Remove -ConfigPath $Settings.KnowledgeConfigPath -Confirm:$false
                            }
                            else { Write-Host '[INFO] Suppression annulee.' }
                        }
                        'Q' { break }
                        default { Write-Warning 'Choix invalide.' }
                    }
                } while ($scheduleChoice -ne 'Q')
            }
            'Q' { return }
            default { Write-Warning 'Choix invalide.' }
        }
    } while ($true)
}

Export-ModuleMember -Function Start-LocalCodexKnowledge,Set-LocalCodexKnowledgeBudget,Read-LocalCodexKnowledgeBudget
