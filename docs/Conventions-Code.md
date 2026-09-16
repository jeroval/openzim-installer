# Conventions du projet

Ce document sert de repère avant toute modification du code.

## Arborescence

| Dossier | Contenu |
|---|---|
| Racine | Lanceur, point d'entrée, README et compatibilité |
| `scripts/` | Scripts PowerShell exécutables appelés par l'assistant |
| `modules/` | Fonctions partagées importées par plusieurs scripts |
| `config/` | Configuration utilisateur et manifeste des sources ZIM |
| `docs/` | Guides destinés aux utilisateurs et contributeurs |
| `templates/` | Instructions IA communes copiées dans les projets |
| `tests/` | Tests Pester et données de test hors réseau |

## Nommage

- Scripts PowerShell : `Verbe-Nom.ps1`, par exemple `Install-LocalAi.ps1`.
- Fonctions : `Verbe-Nom`, avec un verbe PowerShell explicite.
- Paramètres : `PascalCase`, par exemple `LibraryRoot`.
- Variables locales : `camelCase`, par exemple `repositoryRoot`.
- Fichiers JSON : `PascalCase.json`.
- Un nom représente une responsabilité : installation, invocation, test ou
  configuration. Éviter les noms génériques comme `utils.ps1`.

## Repères dans les scripts

Les sections repliables utilisent toujours la syntaxe reconnue par VS Code :

```powershell
# region Nom explicite de la section
# code
# endregion Nom explicite de la section
```

Ordre recommandé :

1. aide PowerShell et paramètres ;
2. initialisation et chemins ;
3. fonctions sans effet externe ;
4. fonctions qui modifient le système ;
5. exécution ou point d'entrée.

## Chemins

- `Start-OpenZimAssistant.ps1` est le seul orchestrateur.
- Les chemins internes sont calculés à partir de `$PSScriptRoot`.
- Aucun script ne dépend du dossier courant du terminal.
- Les chemins relatifs de la configuration sont résolus par rapport au fichier
  ou à la racine du dépôt, selon leur fonction.

## Compatibilité

`openzim.ps1` et `register-zim-update-task.ps1` sont de petits relais conservés
pour les anciennes commandes et tâches Windows. Le nouveau code ne doit pas y
être ajouté.
