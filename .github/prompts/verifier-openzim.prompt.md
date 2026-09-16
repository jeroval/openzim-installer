---
name: 'verifier-openzim'
description: 'Vérifie le serveur MCP, les archives ZIM et la lecture réelle d’un document local.'
agent: 'agent'
tools: ['openzim/*']
---

<!-- openzim-startup-check:begin -->
# Diagnostic de démarrage OpenZIM

Effectue uniquement un diagnostic en lecture seule. Ne crée, ne modifie et ne
supprime aucun fichier. N’utilise pas Internet.

1. Vérifie que l’outil `openzim_list_archives` du serveur MCP `openzim` est disponible.
2. Appelle-le une fois, sans argument :

   ```json
   {}
   ```

   N’utilise pas directement l’outil interne `zim_query` et n’invente aucun
   paramètre supplémentaire.
3. Dans la liste retournée, choisis de préférence une archive
   `docs.python.org`; sinon choisis une archive technique réellement disponible.
4. Vérifie la lecture effective avec `openzim_search_archive`. Fournis uniquement
   son chemin exact dans `zim_file_path` et une question courte dans `query`.
   Pour la documentation Python, demande :
   `What does pathlib.Path.resolve do?`
5. Ne déclare la base opérationnelle que si la liste des archives et la lecture
   documentaire ont toutes les deux réussi.

Réponds exclusivement en français selon ce format :

```text
ÉTAT DE L’AGENT IA LOCAL
- Serveur OpenZIM MCP : OK ou ÉCHEC
- Bibliothèque ZIM : OK ou ÉCHEC — nombre d’archives détectées
- Lecture documentaire : OK ou ÉCHEC
- Fonctionnement hors ligne : NON TESTÉ, sauf si l’absence de réseau est établie

SOURCE LOCALE CONSULTÉE
- Archive : nom exact
- Document : titre exact, si le serveur le fournit
- Apport : information utilisée pour vérifier la lecture

CONCLUSION
Une phrase indiquant si la chaîne est prête et, sinon, l’erreur exacte.
```

Ne confonds jamais la présence de `.vscode/mcp.json` avec une connexion réussie.
Ne prétends jamais avoir consulté une archive si aucun appel d’outil n’a retourné
son contenu.
<!-- openzim-startup-check:end -->
