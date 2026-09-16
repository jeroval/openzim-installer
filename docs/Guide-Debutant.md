# Guide débutant — Assistant OpenZIM MCP

Vous n'avez aucun fichier JSON à modifier manuellement.

## Petit lexique

- **Ollama** : programme qui charge et exécute le modèle IA sur votre ordinateur.
- **GPT-OSS / Qwen** : modèles qui comprennent votre demande et rédigent la
  réponse. Vous pouvez installer l'un, l'autre ou les deux.
- **ZIM** : fichier compressé contenant un site documentaire utilisable hors
  ligne, par exemple Python, MDN ou une communauté Stack Exchange.
- **OpenZIM MCP** : serveur local qui permet au chat de rechercher dans les ZIM.
- **MCP** : protocole par lequel un agent IA demande l'utilisation d'un outil.

En résumé : Ollama fait fonctionner le cerveau, les ZIM contiennent la
documentation et OpenZIM MCP construit le pont entre les deux.

## Démarrage

1. Ouvrez le dossier de l'outil dans l'Explorateur Windows.
2. Double-cliquez sur **`Demarrer-OpenZim.cmd`**.
3. Dans le menu, choisissez **1 — Définir vos besoins et contraintes**.
4. Choisissez l'usage le plus proche de vos projets, puis acceptez ou adaptez
   les valeurs recommandées.
5. Choisissez **3 — Voir le plan de téléchargement** avant tout téléchargement.
6. Si le volume vous convient, choisissez **11 — Installation guidée complète**.

Vous pouvez saisir **A** depuis le menu pour revoir le schéma et le parcours
recommandé. L'accueil affiche également un **Conseil** calculé à partir des
composants réellement détectés, ainsi qu'un parcours en quatre étapes.

L'assistant vous demande confirmation avant les téléchargements volumineux et
avant la création d'une tâche planifiée.

La rubrique **État rapide** détecte Visual Studio Code, Ollama, GPT-OSS 20B,
Qwen2.5-Coder 14B, Qwen 3.5 Agent 9B 32K et Devstral Agent 24B. Si Ollama est
arrêté, les modèles sont indiqués comme non vérifiables ; l'écran d'accueil ne
démarre aucun service.

## Ordre conseillé

Le parcours complet réalise les opérations suivantes :

1. installation ou mise à jour de `uv` et du serveur `openzim-mcp` ;
2. calcul du pack compatible avec le budget configuré ;
3. confirmation du téléchargement ;
4. téléchargement avec reprise en cas d'interruption ;
5. création automatique de `.vscode/mcp.json` et des instructions IA dans
   `.github/copilot-instructions.md` dans le projet choisi ;
6. contrôles de fonctionnement.

### Avant de télécharger

Le budget indiqué concerne uniquement les archives ZIM. Les modèles Ollama
occupent de l'espace en supplément : environ 14 Go pour GPT-OSS 20B, 11 Go
pour Qwen2.5-Coder 14B Q5_K_M, 6,6 Go pour Qwen 3.5 Agent 9B et 15 Go pour
Devstral Small 2 24B. Qwen 3.5 Agent est le choix recommandé : son profil 32K
est créé automatiquement pour limiter la mémoire utilisée dans VS Code.
L'option 3 reste sans gros téléchargement et permet de connaître la taille du
panier documentaire à l'avance.

### Configuration de votre premier projet

L'option 5 attend le dossier racine du projet, par exemple
`C:\Projets\MonApplication`, et non le dossier où cet installateur est stocké.
Elle crée automatiquement :

```text
C:\Projets\MonApplication\.vscode\mcp.json
C:\Projets\MonApplication\.github\copilot-instructions.md
C:\Projets\MonApplication\.github\instructions\openzim-development-standards.instructions.md
C:\Projets\MonApplication\.github\prompts\verifier-openzim.prompt.md
C:\Projets\MonApplication\AGENTS.md
C:\Projets\MonApplication\docs\ai\Guide-Bonnes-Pratiques-Code.md
```

Le premier fichier déclare OpenZIM comme outil MCP. Le second demande à l'agent
de consulter la documentation locale. Les autres fichiers imposent le socle
commun de nommage, conception, sécurité, tests, documentation et méthode de
travail. Les autres serveurs MCP et instructions déjà présents sont conservés.

L'option 5 complète également le `.gitignore` sans supprimer ses règles. Les
fichiers `.vscode/mcp.json` et `.github/copilot-instructions.md` restent locaux,
car le premier contient des chemins propres à l'ordinateur et le second suit la
préférence locale de cet assistant. Les archives `*.zim`, téléchargements
partiels, plans et inventaires locaux sont également exclus. En revanche,
`AGENTS.md`, le guide et les
standards `.github/instructions` restent versionnables : ils constituent les
règles partagées du projet.

### Premier message de chaque conversation

Dans le chat VS Code, saisissez :

```text
/verifier-openzim
```

Le diagnostic vérifie le serveur, demande la liste des archives puis lit un
document réel. Il répond en français et ne déclare un succès que si les appels
OpenZIM ont effectivement retourné des données. Vous pouvez également lancer
`Chat: Run Prompt` depuis la palette de commandes et choisir
`verifier-openzim`.

Après cette opération, rechargez la fenêtre VS Code. La disponibilité réelle
d'OpenZIM dépend de l'extension de chat : elle doit prendre en charge Ollama,
MCP et les appels d'outils.

## Valeurs recommandées

- Dossier : `%USERPROFILE%\OpenZIM\Knowledge\ZIM`
- Budget : `50 Go`
- Mode MCP : `simple`
- Sources optionnelles : `non`

Le chemin `%USERPROFILE%` correspond automatiquement à votre dossier Windows.
Il évite d'avoir besoin des droits administrateur pour créer `C:\AI`.

## Sélection intelligente selon le budget

Le budget est un plafond strict, pas une taille à atteindre obligatoirement.
L'assistant classe les sources par pertinence pour le développement et par
affinité avec votre usage, puis retient la
version la plus récente et ajoute les archives tant qu'elles tiennent dans le
plafond.

Les cinq profils disponibles sont : développement polyvalent, Web et
applications, systèmes/réseaux/DevOps, données/IA et sécurité. Le profil ne
supprime pas arbitrairement les autres domaines : il leur applique un bonus de
priorité lorsque le budget oblige à choisir. La colonne `Affinite` du plan rend
ce choix visible.

- Avec **50 Go**, il privilégie Python, le Web, les petites communautés Stack
  Exchange, les systèmes, la sécurité et une Wikipédia compacte.
- À partir de **75–100 Go**, il peut remplacer une collection compacte par une
  variante plus riche et ajouter des documentations complémentaires.
- Avec **200 Go**, il peut ajouter le Stack Overflow complet lorsque sa taille
  actuelle tient avec le reste du panier.

Les variantes appartenant au même groupe sont exclusives : l'assistant ne
télécharge pas simultanément trois éditions redondantes de Wikipédia. Le plan
affiche la pertinence, la taille et la raison d'une éventuelle exclusion.

Lorsque Stack Overflow complet ne tient pas dans le plafond, l'assistant le
remplace fonctionnellement par un panier de communautés techniques : Code
Review, Computer Science, Data Science, intelligence artificielle, réseaux,
cryptographie, reverse engineering, électronique, Raspberry Pi, Arduino,
robotique, développement de jeux, graphisme et outils de développement. Il ne
prend pas les communautés Stack Exchange sans rapport avec l'informatique.

L'option **3 — Voir le plan** permet de contrôler ce choix sans télécharger de
gros fichier. Pour changer de plafond, utilisez simplement l'option **1 —
Configuration assistée** ; aucun fichier JSON n'est à modifier.

## Que fait chaque choix ?

| Choix | Fonction |
|---:|---|
| 1 | Définit l'usage, le stockage, le budget et le mode par questions/réponses |
| 2 | Installe ou met à jour OpenZIM MCP |
| 3 | Affiche les archives choisies et leur taille, sans les télécharger |
| 4 | Télécharge le pack avec reprise et contrôles |
| 5 | Configure automatiquement MCP et les instructions IA du projet VS Code sélectionné |
| 6 | Vérifie PowerShell, Ollama, les ZIM et MCP ; les modèles installés sont seulement informatifs |
| 7 | Affiche les archives déjà présentes |
| 8 | Recherche et installe les nouvelles versions |
| 9 | Liste d'autres documentations disponibles chez Kiwix |
| 10 | Ouvre le gestionnaire de tâche : créer, vérifier, tester ou supprimer |
| 11 | Lance le parcours guidé avec prévisualisation du panier avant téléchargement |
| 12 | Affiche le sélecteur, installe Ollama s'il manque, puis uniquement les modèles IA choisis |
| 13 | Ferme proprement l'assistant (`0` reste également accepté) |
| A | Affiche l'aide et le schéma du parcours local |

## Comprendre les messages courants

| Message | Signification | Action conseillée |
|---|---|---|
| `non installé` | Le composant n'a pas été trouvé | Utiliser l'option indiquée par la ligne Conseil |
| `PATH à réparer` | Le programme existe mais cette session ne trouve pas encore sa commande | Fermer puis relancer l'assistant ; l'option 2 peut aussi réparer le PATH |
| `service Ollama arrêté` | Ollama est installé mais son API locale ne répond pas | Lancer Ollama ou utiliser l'option 12 |
| `Projet VS Code à configurer` | Les fichiers MCP ne sont pas dans le projet actuellement sélectionné | Utiliser l'option 5 et choisir le bon dossier |
| `EXCLU` dans le plan | L'archive dépasserait le budget ou ferait doublon avec une variante choisie | Augmenter le budget seulement si l'espace disque le permet |

## Premier test dans VS Code

Après l'option 6, rechargez VS Code puis demandez par exemple :

> Recherche d'abord dans OpenZIM une explication de cette erreur Python et
> indique l'archive ou l'article utilisé.

Vérifiez dans le chat qu'un appel à `openzim_search` ou
`openzim_search_archive` est proposé ou exécuté. Une
réponse correcte du modèle sans appel d'outil ne prouve pas que la base ZIM a
été consultée.

## Si Windows bloque le lancement

Cliquez avec le bouton droit sur `Demarrer-OpenZim.cmd`, choisissez
**Propriétés**, cochez **Débloquer** si cette option apparaît, puis relancez-le.
Le lanceur applique la politique d'exécution uniquement à cette session ; il ne
modifie pas la configuration globale de PowerShell.

## Utilisation avancée facultative

Les commandes restent disponibles pour l'automatisation :

```powershell
.\Start-OpenZimAssistant.ps1 -Action Plan
.\Start-OpenZimAssistant.ps1 -Action Install
.\Start-OpenZimAssistant.ps1 -Action InstallAI -InstallGptOss -InstallQwenCoder
.\Start-OpenZimAssistant.ps1 -Action Download
.\Start-OpenZimAssistant.ps1 -Action Configure -ProjectDirectory C:\MonProjet
.\Start-OpenZimAssistant.ps1 -Action Test
```

Cette section est facultative : le menu suffit pour l'utilisation normale.
