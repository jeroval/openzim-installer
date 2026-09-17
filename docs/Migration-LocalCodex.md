# Migration vers Local-Codex

## Audit du 17 septembre 2026

Le dossier de travail autorise est `C:\Users\jeroval\Downloads\test`, remote
`jeroval/test`, revision initiale `54409d1`. Windows et PowerShell 5.1 restent
la plateforme de reference. Aucune suppression ni deprecation effective des
anciens modeles avant certification de la nouvelle chaine.

| Composant | Decision |
|---|---|
| `Start-OpenZimAssistant.ps1`, lanceurs historiques | Conserver comme parcours Knowledge et compatibilite |
| `scripts/Invoke-ZimLibrary.ps1` | Reutiliser catalogue, budget, variantes, reprise `.part`, SHA-256, inventaire et mises a jour |
| `scripts/Invoke-ZimScheduledTask.ps1` | Conserver les taches et leurs anciennes commandes |
| `modules/OpenZim.Common.psm1` | Reutiliser mutex, logs JSONL, retention et instructions gerees |
| `modules/LocalAi.Hardware.psm1` | Reutiliser detection NVIDIA/registre/WMI ; enrichir sans liste de GPU |
| `scripts/Install-LocalAi.ps1` | Conserver installation Ollama et profils historiques |
| `scripts/Install-OpenZimMcp.ps1` | Conserver ; ne pas appeler son upgrade implicite pour une simple configuration Hermes |
| `scripts/OpenZimCompatServer.py` | Conserver les trois outils, puis mesurer le mode direct separement |
| `scripts/Test-LocalAgent.ps1` | Diagnostic historique, pas certification agentique |
| `config/OpenZim.Settings.json`, `ZimSources.json` | Conserver et referencer depuis la nouvelle configuration |
| `tests/OpenZim.Tests.ps1` et fixtures | 22 tests initiaux passes ; conserver la suite offline |
| `.github` | Instructions et prompt presents ; aucun workflow CI existant |
| README, guides, templates | Ajouter le parcours Local-Codex et identifier clairement le parcours historique |

Limites existantes observees : SHA-256 indisponible peut conduire a une
validation par taille ; le diagnostic ne prouve pas une edition par le modele ;
le profil Qwen 32K ne satisfait pas le minimum documente de Hermes. Les anciens
tests contiennent des assertions de texte sur ce profil : les conserver tant
que le parcours historique existe.

## Ordre et fichiers

1. Audit et baseline : ce document, tests existants.
2. Integration additive : `modules/Hermes.psm1`, catalogue Qwen,
   configuration isolee Hermes et client ACP VS Code. Aucune extension agentique
   concurrente ; Ollama conserve son role de runtime.
3. MCP : reprendre les chemins locaux de la passerelle existante dans Hermes,
   sans modifier l'installation OpenZIM lors de Configure.
4. Mesures et validation : modules Benchmark/Certification, rapports locaux,
   scenario agentique dans un dossier temporaire. Une dependance absente ou un
   test non execute interdit la certification.
5. Deprecations : seulement apres certification reelle ; aucune pour l'instant.
6. CLI et etat : point d'entree Local-Codex, candidate/stable/previous,
   preservation des anciennes commandes et des modeles telecharges.
7. Documentation et regression complete.

## Sources et hypotheses

OpenZIM MCP 3.3.3 local : auto-test des trois outils reussi ; recherche
`search all files for Hermes Agent ACP` dans 23 archives sans resultat.
Aucun article local pertinent ne permet de configurer Hermes.

Documentation officielle consultee le 17 septembre 2026 :

- [Installation Hermes](https://hermes-agent.nousresearch.com/docs/getting-started/installation) : installation Windows et HERMES_HOME.
- [Providers](https://hermes-agent.nousresearch.com/docs/integrations/providers) : endpoint Ollama custom et context_length.
- [ACP](https://hermes-agent.nousresearch.com/docs/user-guide/features/acp) : extra acp, `hermes acp --check`, `acp.agents` et client `formulahendry.acp-client`.
- [MCP](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp) : `mcp_servers`, command et args.

Le contexte 65536 est un candidat initial compatible avec le minimum documente,
pas une recommandation universelle ni une certification. Les mesures doivent
rester liees au modele, a son digest, au contexte et aux versions installees.
