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

## 5. Validation hors ligne

1. Terminer tous les telechargements avant ce test.
2. Desactiver temporairement Wi-Fi/Ethernet depuis Windows.
3. Confirmer que `http://127.0.0.1:11434/api/tags` repond encore.
4. Redemarrer le serveur MCP `openzim` dans VS Code.
5. Rejouer les deux scenarios precedents.
6. Verifier dans le Gestionnaire des taches qu'Ollama et OpenZIM restent des
   processus locaux et qu'aucune etape ne reclame une ressource distante.

La coupure reseau doit etre effectuee manuellement : un script ne doit pas
desactiver vos interfaces reseau sans confirmation explicite.

## 6. Mise a jour periodique

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
