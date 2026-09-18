---
name: 'verifier-codex'
description: 'Contrôle la chaîne locale VS Code, ACP, Hermes, Ollama, Qwen et OpenZIM.'
agent: 'agent'
tools: ['execute/runInTerminal', 'openzim/*']
---

# Diagnostic complet de Local-Codex

Effectue uniquement des contrôles en lecture seule. Ne crée, ne modifie et ne
supprime aucun fichier. N’utilise ni Internet ni délégation.

1. Vérifie que `.local-codex/project.json` et
   `.local-codex/Test-LocalCodexHealth.ps1` existent dans le projet.
   S’ils sont absents, arrête le diagnostic et demande d’exécuter l’option
   `2. Initialiser un projet` de Local-Codex.
2. Avec l’outil terminal, exécute exactement depuis la racine du projet :

   ```powershell
   powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .local-codex/Test-LocalCodexHealth.ps1 -Json
   ```

3. Analyse tous les contrôles du JSON retourné. Ne transforme jamais un état
   `FAIL` en succès et regroupe les erreurs dépendantes sous leur cause racine.
4. Vérifie ensuite la connexion MCP réelle de cette conversation en appelant
   `openzim_list_archives` une fois, sans argument. N’utilise pas directement
   l’outil interne `zim_query`.
5. Si la liste réussit, choisis de préférence une archive `docs.python.org`,
   puis appelle `openzim_search_archive` avec son chemin exact et la question
   courte `What does pathlib.Path.resolve do?`.
6. Ne déclare Local-Codex prêt que si le script retourne `PASS`, si les archives
   sont listées et si une lecture documentaire retourne réellement du contenu.
7. Pour chaque défaut, fournis sa cause probable, la preuve observée et une
   action corrective précise. Ne tente aucune réparation pendant ce diagnostic.

Réponds exclusivement en français selon ce format :

```text
BILAN LOCAL-CODEX
- Projet : OK ou ÉCHEC — chemin contrôlé
- Visual Studio Code / ACP Client : OK ou ÉCHEC
- Hermes / ACP : OK ou ÉCHEC — version ou erreur exacte
- Ollama : OK ou ÉCHEC — version
- Modèle local : OK ou ÉCHEC — nom et contexte
- Appels d’outils du modèle : OK ou ÉCHEC
- Retry automatique : OK ou ÉCHEC — nombre de tentatives
- OpenZIM MCP : OK ou ÉCHEC
- Bibliothèque ZIM : OK ou ÉCHEC — nombre d’archives
- Lecture documentaire réelle : OK ou ÉCHEC
- Fonctionnement hors ligne : NON TESTÉ, sauf si l’absence de réseau est établie

EMPLACEMENTS
- État Local-Codex : chemin
- Hermes : chemin
- Profil Hermes : chemin
- Modèles Ollama : chemin
- Bibliothèque ZIM : chemin

SOURCE LOCALE CONSULTÉE
- Archive : nom exact
- Document : titre exact
- Apport : information utilisée pour confirmer la lecture

CONCLUSION
PRÊT ou NON PRÊT.

DÉFAUTS ET CORRECTIONS
- Pour chaque erreur : composant, preuve exacte, cause racine probable et action corrective.
- Si aucune erreur : `Aucun défaut détecté par les contrôles exécutés.`
```

La présence d’un fichier de configuration ne suffit jamais à prouver qu’un
service répond. N’affirme pas qu’un test a réussi s’il n’a pas été exécuté.
