# Base documentaire locale OpenZIM pour agent IA

Cette boite a outils installe OpenZIM MCP, construit une bibliotheque Kiwix
classee et configure VS Code. Les telechargements ne sont jamais lances par
defaut.

## Résultat obtenu

Après le parcours guidé, vous disposez d'un assistant de développement local :

```text
Question dans VS Code
        |
        v
Extension de chat compatible Ollama et MCP
        |
        +----> Ollama exécute GPT-OSS ou Qwen sur votre ordinateur
        |
        +----> OpenZIM MCP recherche dans les archives Kiwix locales
```

Les archives restent sur votre disque et peuvent être consultées sans Internet.
Le modèle ne lit toutefois pas directement les fichiers `.zim` : l'extension
de chat de VS Code doit prendre en charge MCP et autoriser les appels d'outils.

## Prérequis

- Windows 10 ou Windows 11 en 64 bits ;
- PowerShell 5.1 ou version ultérieure ;
- une connexion Internet pour l'installation et les téléchargements initiaux ;
- suffisamment d'espace disque : budget ZIM choisi, plus environ 14 Go pour
  GPT-OSS 20B et 11 Go pour Qwen2.5-Coder 14B si les deux sont installés ;
- idéalement 16 Go de mémoire vive ou plus pour GPT-OSS 20B. Les performances
  réelles dépendent fortement du processeur, de la mémoire et du GPU.

Les droits administrateur ne sont normalement pas nécessaires lorsque les
dossiers proposés par défaut sont conservés.

## Pour débuter : aucun JSON à modifier

Double-cliquez sur **`Demarrer-OpenZim.cmd`**. Un menu en français permet de
configurer le dossier, le budget, les contenus optionnels, l'installation du
serveur OpenZIM MCP, les téléchargements et VS Code. Les valeurs sont
enregistrées automatiquement.

L'accueil détecte également Visual Studio Code, Ollama, GPT-OSS 20B et
Qwen2.5-Coder 14B sans démarrer de service ni télécharger de modèle.

Consultez [GUIDE-DEBUTANT.md](GUIDE-DEBUTANT.md) pour le parcours pas à pas.

Dans le menu, saisissez **A** à tout moment pour afficher l'explication du
parcours complet. La ligne **Conseil** de l'accueil indique automatiquement la
prochaine étape recommandée.

## Premier lancement conseillé

1. Téléchargez le dépôt GitHub puis décompressez-le dans un dossier permanent.
2. Double-cliquez sur `Demarrer-OpenZim.cmd`.
3. Utilisez **1 — Configuration assistée** et conservez le mode `simple` pour
   commencer.
4. Utilisez **12** pour installer Ollama et au moins un modèle.
5. Utilisez **2** pour installer OpenZIM MCP.
6. Utilisez **3** pour examiner le panier ZIM sans téléchargement.
7. Utilisez **4** lorsque le volume vous convient.
8. Créez ou ouvrez votre projet dans VS Code, puis utilisez **5** en indiquant
   son dossier racine.
9. Utilisez **6**, rechargez la fenêtre VS Code et réalisez le test décrit dans
   `LOCAL_AGENT_VALIDATION.md`.

L'option **11 — Installation guidée complète** regroupe ce parcours et conserve
les demandes de confirmation avant les téléchargements importants.

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

# Installer Ollama et les deux modeles locaux (environ 25 Go)
.\openzim.ps1 -Action InstallAI -InstallGptOss -InstallQwenCoder

# 3. Telecharger les sources principales avec reprise et controle SHA-256
.\openzim.ps1 -Action Download

# 4. Configurer MCP et les instructions IA du projet
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
| `InstallAI` | Installe Ollama s'il manque et les modeles IA explicitement choisis |
| `Download` | Telecharge les archives manquantes et reprend les `.part` |
| `Update` | Recherche et telecharge les nouvelles editions |
| `Configure` | Cree ou complete `.vscode/mcp.json` et `.github/copilot-instructions.md` |
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
- Les installateurs sont idempotents : les composants et modèles déjà présents
  ne sont pas téléchargés une seconde fois.
- L'accueil ne démarre pas Ollama. Si son service est arrêté, les modèles sont
  affichés comme non vérifiables plutôt que comme absents.

Executer les tests hors reseau :

```powershell
Invoke-Pester .\openzim-installer\OpenZim.Tests.ps1
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
- `install-local-ai.ps1` : installation idempotente d'Ollama et des modeles locaux ;
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

## Ce que l'outil ne fait pas

- Il n'installe pas automatiquement une extension VS Code particulière, car le
  choix dépend du client utilisé pour connecter Ollama et MCP.
- Il ne garantit pas qu'un modèle appellera un outil à chaque question ; les
  instructions du projet l'y encouragent et le scénario de validation permet de
  le vérifier.
- Il ne réduit pas artificiellement les très grandes archives : une source qui
  dépasse le budget est exclue et expliquée dans le plan.
