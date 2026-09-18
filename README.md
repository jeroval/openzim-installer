# Local-Codex

Local-Codex installe sous Windows un agent de développement local utilisable
dans Visual Studio Code. Une installation globale dessert tous vos projets.
Le [cahier des besoins](docs/Cahier-des-besoins.md) définit les critères produit
et les preuves nécessaires avant de déclarer une installation fonctionnelle.
Les frontières entre interface, cas d’usage et intégrations sont décrites dans
[l’architecture](docs/Architecture.md).

```text
Visual Studio Code -> ACP Client -> Hermes Agent -> Ollama -> Qwen 3.5
                              |
                              +-> OpenZIM MCP -> archives ZIM locales
```

ACP est une exigence de Local-Codex, pas un mode optionnel. Il transporte entre
VS Code et Hermes la conversation, le streaming, l'activité des outils, les
commandes terminal, les demandes d'autorisation et les modifications de
fichiers. Sans liaison ACP validée, Local-Codex refuse de considérer la chaîne
comme fonctionnelle : un chatbot Ollama dans une barre latérale ne suffit pas.

## Démarrage

Double-cliquez sur `Start-LocalCodex.cmd`, puis suivez le menu :

```text
1. Installer Local-Codex
2. Initialiser un projet
3. Vérifier Local-Codex
4. Gérer la documentation locale
5. Mettre à jour Local-Codex
6. Paramètres
7. Désinstaller Local-Codex

Q. Quitter
```

L’installation détecte et réutilise Git, Visual Studio Code, uv, Ollama,
Hermes, ACP Client et OpenZIM MCP. `uv` fournit à Hermes son environnement
Python 3.11 isolé, sans dépendre d’un éventuel Python global incompatible. Les
composants manquants sont installés automatiquement. L’état global est placé dans
`%LOCALAPPDATA%\Local-Codex` ; modèles, runtimes et archives ZIM ne sont jamais
copiés dans les projets.

## Initialiser un projet

L’option 2 accepte un dossier vide, un projet existant ou un dépôt Git. Elle
configure ACP et les instructions de l’agent. Un dépôt Git local n’est initialisé
qu’après confirmation ; aucun dépôt distant, commit ou push n’est créé.

## Modèle local

Le catalogue est limité à Qwen 3.5 jusqu’à 9B : `0.8b`, `2b`, `4b` et
`9b-q4_K_M`. Un seul modèle est destiné à être installé. Hermes exige au moins
64K de contexte pour le fonctionnement agentique avec outils. Cette valeur est
un plancher absolu : la recommandation matérielle peut choisir un modèle plus
petit, mais ne réduit jamais le contexte sous 64K pour économiser la VRAM.
Benchmark et certification doivent valider le profil sur chaque machine.

## Vérification et documentation

La vérification contrôle le client ACP, le démarrage ACP de Hermes et la
cohérence du contexte Ollama/Hermes (64K minimum). Elle exécute ensuite un projet temporaire cassé
pour prouver lecture, recherche, édition, terminal, tests, correction et retest.
Le menu Documentation installe OpenZIM MCP, planifie le panier, télécharge avec
reprise, affiche l’inventaire et recherche les mises à jour. Sa configuration se
trouve dans `config/Knowledge.Settings.json`. Le même menu permet de créer,
inspecter, tester ou supprimer la tâche Windows de mise à jour hebdomadaire ; la
suppression de cette tâche conserve toujours les archives.

## Commandes avancées

```powershell
.\Local-Codex.ps1 -Action Install -DownloadModel
.\Local-Codex.ps1 -Action InitializeProject -ProjectDirectory C:\Projets\Application
.\Local-Codex.ps1 -Action Verify -ProjectDirectory C:\Projets\Application
.\Local-Codex.ps1 -Action Verify -ProjectDirectory C:\Projets\Application -Advanced
.\Local-Codex.ps1 -Action Settings
```

Pendant l'installation, Local-Codex affiche neuf etapes numerotees, explique le
role de chaque composant et termine par leurs emplacements reels. L'option 3
affiche un bilan de sante colorise avec versions, causes d'erreur, actions
conseillees, materiel detecte et chemins d'installation. Un chemin se terminant
par `.vscode` est automatiquement ramene a la racine du projet. L'option 6
permet de revoir les emplacements sans relancer une installation.

Les projets, dépôts Git et archives ZIM ne sont jamais supprimés silencieusement.
