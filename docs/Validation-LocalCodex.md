# Compte rendu de migration — 17 septembre 2026

Une premiere tranche fonctionnelle est implementee et validee sur cette machine
Windows. La chaine Hermes / ACP / Ollama / Qwen / OpenZIM a passe le scenario
agentique et le profil local a ete promu `certified`. Cela ne signifie pas que
toutes les ambitions du gestionnaire multi-machines sont deja implementees.

## Fichiers crees

| Groupe | Fichiers |
| --- | --- |
| Entree | `Local-Codex.ps1`, `Start-LocalCodex.cmd` |
| Configuration | `config/LocalCodex.Settings.json`, `config/ModelCatalog.json` |
| Modules | `modules/LocalCodex.Common.psm1`, `Hardware.psm1`, `Models.psm1`, `Hermes.psm1`, `OpenZim.psm1`, `Doctor.psm1`, `Benchmark.psm1`, `Certification.psm1`, `Updates.psm1` |
| Adaptateurs | `scripts/Measure-LocalCodex.py`, `Test-LocalCodexAcp.py`, `Start-LocalCodexAcp.ps1` |
| Tests | `tests/LocalCodex.Tests.ps1`, `tests/test_localcodex.py` |
| Documentation | `docs/Migration-LocalCodex.md`, `docs/Local-Codex.md`, ce compte rendu |

## Fichiers modifies

- `README.md` : nouveau point d'entree et lien vers le parcours historique.
- `AGENTS.md` : politique de migration, verification et preservation.
- `.gitignore` : etat Local-Codex et configurations VS Code propres a la machine.
- `modules/OpenZim.Common.psm1` : marqueur UTF-8 BOM pour que PowerShell 5.1
  preserve les accents des instructions generees.
- `scripts/OpenZimCompatServer.py` : la recherche generique formule explicitement
  une recherche multi-archives, ce qui evite `No ZIM File Specified`.
- `tests/OpenZim.Tests.ps1` : analyse syntaxique limitee au code du projet,
  sans parcourir les runtimes tiers installes dans le repertoire ignore.

Aucun fichier, modele, archive ou ancien parcours supprime. Aucune branche legacy
retiree. Les modifications sont locales ; aucun commit ni push n'a ete effectue.

## Fonctionnalites livrees

CLI et menu ; configuration structuree ; catalogue Qwen extensible ; detection
materielle reutilisee et enrichie ; installation Hermes isolee et epinglee ;
profil Ollama distinct ; fusion ACP VS Code ; connexion OpenZIM ; Doctor ;
microbenchmark en streaming ; certification reelle avec fixtures ; promotion
controlee et pointeurs stable/previous/candidate ; rollback des profils ;
desactivation conservant les donnees ; mutex et journalisation reutilises.

Les sessions, la memoire, les outils et les skills restent geres par Hermes.
Les mecanismes Knowledge historiques sont conserves : catalogue, budget,
selection, reprise, controles, inventaire, mises a jour et taches periodiques.

## Verifications executees

| Verification | Resultat |
| --- | --- |
| Pester 3.4 / PowerShell 5.1, suite historique et nouveaux tests | 33 reussis, 0 echec |
| unittest Python, fixtures et mocks sans reseau | 9 reussis, 0 echec |
| Analyse syntaxique PowerShell | PASS, incluse dans Pester |
| `python -m compileall -q scripts tests` | PASS |
| `git diff --check` | PASS ; avertissements habituels LF/CRLF |
| `hermes acp --check` | PASS |
| Lanceur ACP PowerShell : echange initialize reel | PASS |
| Doctor, dix prerequis | PASS ; Doctor seul ne lance pas le scenario |
| OpenZIM : trois outils et bibliotheque reelle | PASS, 23 archives accessibles |
| Benchmark du candidat, trois repetitions | PASS |
| Scenario ACP : 16 controles agentiques | PASS |
| Promotion puis Configure sur le stable | PASS, profil preserve |
| Recreation du profil Ollama deja present | PASS, alias reutilise |

La certification finale est datee `2026-09-17T17:07:58Z`. Les preuves locales sont
dans `.local-codex/certification.json`, `benchmark.json`, `doctor.json`,
`offline-tests.txt` et les sous-dossiers `runs/`. Les essais precedents en echec
ont ete conserves. Ils ont permis de corriger les extras MCP manquants, les appels
MCP imbriques, les chemins Git Bash et le decodage des resultats Hermes suivis
d'un avertissement. Aucun controle obligatoire n'a ete supprime pour obtenir PASS.

Le scenario couvre recherche, lecture, plan, diagnostic, patch de deux fichiers,
terminal, compilation, echec observe, correction, retest, preservation des tests,
appel OpenZIM et contenu documentaire reel. Les deux tests de la fixture echouent
avant la correction et passent apres. Il s'agit d'un scenario assiste en trois
etapes, pas d'une evaluation exhaustive de l'autonomie du modele.

## Machine et mesures

Windows 11, Ryzen 7 7800X3D, environ 31 Go de RAM utilisable, RTX 4070 SUPER 12 Go.
Hermes 0.21.3 a la revision `64ea66b03d44ead9ffea48161132e5deca5d255a`, Python
3.11.16, Ollama 0.34.1, OpenZIM MCP 3.3.3, VS Code 1.138.0, ACP Client 0.2.0.
Modele existant `qwen3.5:9b-q4_K_M`, alias Local-Codex au contexte 65536.
Aucun nouveau gros modele ni ZIM telecharge pour ces tests.

Dernier microbenchmark : environ **69 a 72 tokens/s**, TTFT de **0,04 a 0,57 s**,
chargement a chaud d'environ **0,002 s**. Pics echantillonnes machine entiere :
RAM jusqu'a 24,2 milliards d'octets, VRAM jusqu'a 9927 Mio. Ces chiffres ne sont
pas la consommation exclusive du modele et ne mesurent pas un contexte rempli
de 65536 tokens. Le premier essai a froid n'est pas garanti reproductible.

## Sources et adaptation

Source OpenZIM effectivement consultee : archive
`docs.python.org_en_all_2026-08.zim`, article **unittest — Unit testing framework**,
chemin Python **3.0** `docs.python.org/release/3.0/library/unittest.html`.
Apport : notions TestCase/assertions ; ne pas confondre cette version documentaire
avec Python 3.11 utilise pour les tests. Aucune documentation Hermes pertinente
n'a ete trouvee dans les archives locales.

La configuration Hermes est fondee sur les sources officielles citees dans
[l'audit](Migration-LocalCodex.md), ainsi que
[Tool Search](https://hermes-agent.nousresearch.com/docs/user-guide/features/tool-search).
Le code et la documentation de la revision epinglee confirment
`tools.tool_search.enabled: off`. Cette option expose directement les schemas des
trois outils MCP : le candidat 9B construisait mal les appels imbriques par defaut.
Les seuils materiels du catalogue sont des hypotheses initiales, pas des resultats
de certification universels.

## Limites et suite recommandee

PSScriptAnalyzer n'est pas installe : pas de resultat de linter revendique.
L'interface graphique ACP dans VS Code, une installation Windows vierge, le
fonctionnement avec reseau physiquement coupe, les autres GPUs/OS et les gros
contextes n'ont pas ete testes. Aucun second stable reel n'existe encore : le
rollback a ete teste sur fixtures, pas entre deux installations de production.

La priorite suivante est un optimiseur comparant plusieurs candidats deja
disponibles (taille, quantification, contexte), puis les mises a jour et le rollback
des binaires partages Ollama/OpenZIM. La desinstallation complete, la migration des
sessions entre profils et une politique native de delegation restent a terminer.
La certification devrait ensuite etre repetee sur davantage de projets et de
machines avant toute deprecation des parcours historiques. Voir aussi les
[limites operationnelles](Local-Codex.md).
