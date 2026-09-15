# Base documentaire locale OpenZIM pour agent IA

Cette boite a outils installe OpenZIM MCP, construit une bibliotheque Kiwix
classee et configure VS Code. Les telechargements ne sont jamais lances par
defaut.

## Pour débuter : aucun JSON à modifier

Double-cliquez sur **`Demarrer-OpenZim.cmd`**. Un menu en français permet de
configurer le dossier, le budget, les contenus optionnels, l'installation du
serveur OpenZIM MCP, les téléchargements et VS Code. Les valeurs sont
enregistrées automatiquement.

Consultez [GUIDE-DEBUTANT.md](GUIDE-DEBUTANT.md) pour le parcours pas à pas.

Le dossier proposé par défaut est
`%USERPROFILE%\OpenZIM\Knowledge\ZIM`, accessible sans droits administrateur.

Les valeurs communes sont centralisees dans `openzim.config.json` : dossier
de bibliotheque, catalogue, budget, marge disque, mode MCP, controles,
tentatives reseau et retention des journaux. Un autre fichier peut etre
selectionne avec `-ConfigPath`.

Le profil par defaut applique un budget maximal de **50 Go**. Les archives
sont traitees selon leur pertinence et une archive qui ferait depasser ce
plafond est marquee `EXCLU` dans le plan. Le panier evolue automatiquement :
les variantes compactes sont privilegiees a 50 Go, des collections plus riches
sont debloquees a 100 Go, et les tres grandes bases peuvent etre ajoutees a
200 Go lorsqu'elles tiennent avec le reste. Les variantes redondantes d'une
meme source sont mutuellement exclusives.

> La version actuelle de Stack Overflow anglais depasse a elle seule 100 Go.
> Elle est donc detectee mais automatiquement exclue du profil 50 Go. Le
> script ne telecharge jamais une ancienne edition uniquement pour contourner
> le budget.

## Utilisation avancée en ligne de commande

```powershell
# 1. Voir ce qui serait telecharge et le volume total
.\openzim.ps1 -Action Plan

# 2. Installer uv et OpenZIM MCP
.\openzim.ps1 -Action Install

# 3. Telecharger les sources principales avec reprise et controle SHA-256
.\openzim.ps1 -Action Download

# 4. Configurer .vscode/mcp.json
.\openzim.ps1 -Action Configure -Mode simple

# 5. Controler l'environnement local
.\openzim.ps1 -Action Test
```

`-Action All` enchaine ces operations. Il peut telecharger un volume tres
important ; toujours executer `Plan` auparavant.

Pour choisir un autre plafond :

```powershell
.\openzim.ps1 -Action Plan -MaxLibrarySizeGB 150
.\openzim.ps1 -Action Download -MaxLibrarySizeGB 150
```

`-AllowBudgetOverflow` existe pour un choix volontaire, mais désactive la
protection de taille.

Les archives Dart et Bootstrap sont optionnelles :

```powershell
.\openzim.ps1 -Action Plan -IncludeOptional
.\openzim.ps1 -Action Download -IncludeOptional
```

## Actions disponibles

| Action | Effet |
|---|---|
| `Discover` | Exporte les documentations de developpement detectees dans le catalogue OPDS |
| `Plan` | Selectionne les versions recentes et calcule le volume |
| `Install` | Installe/met a jour uv et OpenZIM MCP |
| `Download` | Telecharge les archives manquantes et reprend les `.part` |
| `Update` | Recherche et telecharge les nouvelles editions |
| `Configure` | Cree ou complete `.vscode/mcp.json` |
| `Status` | Inventorie les archives locales |
| `Test` | Controle les commandes, Ollama, les modeles et MCP |
| `RegisterUpdate` | Cree une verification hebdomadaire dans le Planificateur Windows |

## Fiabilite et diagnostic

- Un mutex Windows empeche deux executions de gerer simultanement la meme
  bibliotheque.
- Les evenements sont ecrits en JSON Lines dans `.logs` avec les niveaux
  `INFO`, `WARNING` et `ERROR`.
- Les anciens logs sont supprimes suivant `logs.retentionDays`.
- `download-plan.json` et `zim-inventory.json` sont publies par renommage
  atomique d'un fichier temporaire.
- L'inventaire conserve l'URL, la date du catalogue, les tailles attendue et
  locale, le chemin et le resultat de validation.

Executer les tests hors reseau :

```powershell
Invoke-Pester .\tests\OpenZim.Tests.ps1
```

## Mise a jour

```powershell
.\openzim.ps1 -Action Update
```

Par securite, les anciennes editions sont conservees. Pour les supprimer
seulement apres le telechargement et la validation de la nouvelle :

```powershell
.\openzim.ps1 -Action Update -RemovePrevious
```

Enregistrer une verification hebdomadaire :

```powershell
.\openzim.ps1 -Action RegisterUpdate
```

Kiwix ne fournit pas encore de mise a jour differentielle des ZIM : une
nouvelle edition doit etre telechargee entierement. La reprise concerne un
fichier interrompu de la meme edition.

## Fichiers

- `openzim.ps1` : point d'entree ;
- `install-openzim-mcp.ps1` : installation et configuration MCP ;
- `manage-zim-library.ps1` : catalogue, selection, telechargement et mise a jour ;
- `zim-sources.json` : sources, expressions de selection et categories ;
- `register-zim-update-task.ps1` : tache planifiee ;
- `test-local-agent.ps1` : diagnostic local ;
- `AGENTS.md` : politique de priorisation de la documentation locale ;
- `LOCAL_AGENT_VALIDATION.md` : scenarios GPT-OSS et Qwen hors ligne.

## Limites de validation

Le script peut verifier Ollama, les modeles, les fichiers ZIM et la
configuration MCP. La preuve qu'un modele choisit effectivement `zim_query`
doit etre faite dans le chat VS Code : suivez les scenarios de
`LOCAL_AGENT_VALIDATION.md`.
