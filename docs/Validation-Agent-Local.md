# Validation de l'agent IA local

## 1. Controle automatique

```powershell
.\scripts\Test-LocalAgent.ps1 -LibraryRoot 'C:\AI\Knowledge\ZIM'
```

Le controle verifie les executables, les archives ZIM, `.vscode/mcp.json`,
l'API locale Ollama et la presence des modeles attendus.

Pour produire une liste des autres documentations de developpement detectees
dans le catalogue Kiwix :

```powershell
.\Start-OpenZimAssistant.ps1 -Action Discover
```

## 2. Controle MCP dans VS Code

1. Ouvrir la palette de commandes.
2. Executer `MCP: List Servers`.
3. En mode simple, verifier que `openzim` est demarre et que les outils
   `openzim_list_archives`, `openzim_search` et `openzim_search_archive` sont visibles.
   En mode avance, les outils OpenZIM complets restent affiches.
4. En cas d'erreur, ouvrir `Show Output` pour voir les journaux du serveur.

## 2 bis. Diagnostic du premier chat

Dans une nouvelle conversation en mode Agent, lancez `/verifier-openzim`. Le
résultat doit confirmer séparément le serveur MCP, l'inventaire des archives et
la lecture effective d'un document. Une simple présence de `mcp.json` ne suffit
pas. Si la commande n'est pas proposée, exécutez `Chat: Run Prompt` depuis la
palette de commandes et sélectionnez `verifier-openzim`.

Si une ancienne configuration affiche seulement `zim_query` en mode simple,
relancez l'option 5 de l'assistant. Elle remplacera cette configuration par la
passerelle compatible GPT-OSS après un auto-test local des archives.

## 3. Scenario GPT-OSS 20B

Selectionner `gpt-oss:20b`, puis demander :

> Consulte obligatoirement OpenZIM. Recherche une explication de l'erreur
> Python `RuntimeError: context has already been set`, cite l'archive et
> propose une correction minimale.

La reponse est valide si l'historique d'outils montre un appel OpenZIM et si
la reponse identifie la source locale au lieu de repondre uniquement de
memoire.

## 4. Scenario Qwen2.5-Coder

Selectionner une variante locale de `qwen2.5-coder`, puis demander :

> Consulte obligatoirement OpenZIM. Trouve la documentation de
> `AbortController` dans MDN, donne un exemple JavaScript court et indique
> l'archive utilisee.

La reponse est valide si OpenZIM est appele, si MDN est cite et si l'exemple
correspond au passage recupere.

## 5. Scenario Devstral Agent 24B

Selectionner `devstral-small-2:24b-instruct-2512-q4_K_M`, puis demander :

> Agis comme un agent de developpement. Consulte d'abord OpenZIM pour trouver
> la documentation de `pathlib.Path`, cite l'archive utilisee, puis propose
> une modification courte limitee a un seul fichier. Ne modifie rien avant
> d'avoir presente ton plan.

La reponse est valide si Devstral effectue un veritable appel d'outil OpenZIM,
cite la source locale et respecte la sequence recherche, plan, modification.

## Erreur HTTP 500 pendant une modification de code

Le message `error parsing tool call` avec un contenu `apply_patch` signifie que
le modèle a produit un appel JSON invalide avant l'exécution du patch. Ce n'est
pas une erreur OpenZIM et le fichier demandé n'a normalement pas été modifié.

1. Démarrez une nouvelle conversation pour ne pas conserver l'appel invalide.
2. Demandez une modification courte, limitée à un fichier et à une seule méthode.
3. Exigez des chemins relatifs au projet dans les patchs.
4. Si GPT-OSS échoue encore, essayez Devstral Small 2, proposé dans le sélecteur
   précisément pour le code agentique et les appels d'outils. Qwen2.5-Coder peut
   produire l'appel sous forme de texte selon son template ; vérifiez donc qu'un
   véritable appel apparaît dans l'historique.
5. Une mise à jour d'Ollama ou du modèle peut modifier ce comportement : relancez
   l'option 6 après chaque mise à jour importante.

## 6. Validation hors ligne

1. Terminer tous les telechargements avant ce test.
2. Desactiver temporairement Wi-Fi/Ethernet depuis Windows.
3. Confirmer que `http://127.0.0.1:11434/api/tags` repond encore.
4. Redemarrer le serveur MCP `openzim` dans VS Code.
5. Rejouer les scenarios precedents avec les modeles installes.
6. Verifier dans le Gestionnaire des taches qu'Ollama et OpenZIM restent des
   processus locaux et qu'aucune etape ne reclame une ressource distante.

La coupure reseau doit etre effectuee manuellement : un script ne doit pas
desactiver vos interfaces reseau sans confirmation explicite.

## 7. Mise a jour periodique

Afficher d'abord le plan :

```powershell
.\scripts\Invoke-ZimLibrary.ps1 -Action Plan
```

Le plan applique par defaut une limite de 50 Go et explique toute exclusion.

Mettre a jour immediatement :

```powershell
.\scripts\Invoke-ZimLibrary.ps1 -Action Update
```

Enregistrer une verification hebdomadaire :

```powershell
.\scripts\Invoke-ZimScheduledTask.ps1 -DayOfWeek Sunday -At '03:00'
```

Pour supprimer les anciennes editions seulement apres validation de la
nouvelle archive, ajouter `-RemovePrevious`.
