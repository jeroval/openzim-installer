#requires -Version 5.1

Set-StrictMode -Version Latest

function Start-LocalCodexKnowledge {
    param([Parameter(Mandatory)] $Settings)

    $root = Split-Path -Parent $PSScriptRoot
    $manager = Join-Path $root 'scripts\Invoke-ZimLibrary.ps1'
    $installer = Join-Path $root 'scripts\Install-OpenZimMcp.ps1'
    $scheduler = Join-Path $root 'scripts\Invoke-ZimScheduledTask.ps1'
    do {
        Write-Host "`nDOCUMENTATION LOCALE`n"
        Write-Host '1. Installer ou reparer OpenZIM MCP'
        Write-Host '2. Voir le plan de telechargement'
        Write-Host '3. Telecharger les archives selectionnees'
        Write-Host '4. Rechercher et installer les mises a jour'
        Write-Host '5. Afficher les archives installees'
        Write-Host '6. Gerer la mise a jour hebdomadaire'
        Write-Host 'Q. Retour'
        $choice = (Read-Host 'Choix').Trim().ToUpperInvariant()
        switch ($choice) {
            '1' { & $installer -Version $Settings.openzim.version }
            '2' { & $manager -Action Plan -ConfigPath $Settings.KnowledgeConfigPath }
            '3' { & $manager -Action Download -ConfigPath $Settings.KnowledgeConfigPath }
            '4' { & $manager -Action Update -ConfigPath $Settings.KnowledgeConfigPath }
            '5' { & $manager -Action Status -ConfigPath $Settings.KnowledgeConfigPath }
            '6' {
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

Export-ModuleMember -Function Start-LocalCodexKnowledge
