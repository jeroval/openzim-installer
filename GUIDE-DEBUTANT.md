# Guide débutant — Assistant OpenZIM MCP

Vous n'avez aucun fichier JSON à modifier manuellement.

## Démarrage

1. Ouvrez le dossier de l'outil dans l'Explorateur Windows.
2. Double-cliquez sur **`Demarrer-OpenZim.cmd`**.
3. Dans le menu, choisissez **1 — Configuration assistée**.
4. Appuyez sur Entrée pour accepter les valeurs recommandées.
5. Choisissez **3 — Voir le plan de téléchargement** avant tout téléchargement.
6. Si le volume vous convient, choisissez **11 — Installation guidée complète**.

L'assistant vous demande confirmation avant les téléchargements volumineux et
avant la création d'une tâche planifiée.

## Ordre conseillé

Le parcours complet réalise les opérations suivantes :

1. installation ou mise à jour de `uv` et du serveur `openzim-mcp` ;
2. calcul du pack compatible avec le budget configuré ;
3. confirmation du téléchargement ;
4. téléchargement avec reprise en cas d'interruption ;
5. création automatique de `.vscode/mcp.json` dans le projet choisi ;
6. contrôles de fonctionnement.

## Valeurs recommandées

- Dossier : `%USERPROFILE%\OpenZIM\Knowledge\ZIM`
- Budget : `50 Go`
- Mode MCP : `simple`
- Sources optionnelles : `non`

Le chemin `%USERPROFILE%` correspond automatiquement à votre dossier Windows.
Il évite d'avoir besoin des droits administrateur pour créer `C:\AI`.

## Sélection intelligente selon le budget

Le budget est un plafond strict, pas une taille à atteindre obligatoirement.
L'assistant classe les sources par pertinence pour le développement, retient la
version la plus récente et ajoute les archives tant qu'elles tiennent dans le
plafond.

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
| 1 | Modifie la configuration par questions/réponses |
| 2 | Installe ou met à jour OpenZIM MCP |
| 3 | Affiche les archives choisies et leur taille, sans les télécharger |
| 4 | Télécharge le pack avec reprise et contrôles |
| 5 | Configure automatiquement le projet VS Code sélectionné |
| 6 | Vérifie PowerShell, Ollama, les modèles, les ZIM et le serveur MCP |
| 7 | Affiche les archives déjà présentes |
| 8 | Recherche et installe les nouvelles versions |
| 9 | Liste d'autres documentations disponibles chez Kiwix |
| 10 | Programme une vérification hebdomadaire |
| 11 | Lance le parcours complet guidé |

## Si Windows bloque le lancement

Cliquez avec le bouton droit sur `Demarrer-OpenZim.cmd`, choisissez
**Propriétés**, cochez **Débloquer** si cette option apparaît, puis relancez-le.
Le lanceur applique la politique d'exécution uniquement à cette session ; il ne
modifie pas la configuration globale de PowerShell.

## Utilisation avancée facultative

Les commandes restent disponibles pour l'automatisation :

```powershell
.\openzim.ps1 -Action Plan
.\openzim.ps1 -Action Install
.\openzim.ps1 -Action Download
.\openzim.ps1 -Action Configure -ProjectDirectory C:\MonProjet
.\openzim.ps1 -Action Test
```

Cette section est facultative : le menu suffit pour l'utilisation normale.
