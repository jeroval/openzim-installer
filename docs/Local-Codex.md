# Local-Codex : utilisation et limites

Le nouveau parcours Windows PowerShell 5.1 relie VS Code (client ACP), Hermes,
Ollama/Qwen et la passerelle OpenZIM existante. Double-cliquer
`Start-LocalCodex.cmd` pour ouvrir le menu. Les anciennes commandes restent disponibles.
Le [compte rendu de validation](Validation-LocalCodex.md) distingue les controles
reussis sur la machine de developpement des limites encore ouvertes.

## Commandes

Depuis la racine du depot :

```powershell
.\Local-Codex.ps1 -Action Plan
.\Local-Codex.ps1 -Action Install
.\Local-Codex.ps1 -Action Doctor
.\Local-Codex.ps1 -Action Benchmark
.\Local-Codex.ps1 -Action Certify -Promote
.\Local-Codex.ps1 -Action Status
```

`Install` prepare les composants, configure le projet, puis lance benchmark et
certification. Git pour Windows et VS Code sont des prerequis. Ollama doit etre
joignable localement. L'installation initiale de Hermes et de ses dependances
necessite Internet. Un modele absent exige explicitement `-DownloadModel` ; aucun
ZIM n'est telecharge par ce parcours. `-SkipValidation` prepare seulement un candidat.

`Configure` reutilise les composants presents. `-ProjectDirectory` cible le projet
VS Code ; `-ConfigPath` selectionne une configuration ; `-StateDirectory` isole
les runtimes et profils. `-WhatIf` permet de simuler les actions de modification.
Les reglages VS Code existants sont preserves. Un fichier JSONC avec commentaires
ou une configuration Hermes modifiee manuellement exige une fusion manuelle.

Dans VS Code, ouvrir le client **ACP Client**, puis selectionner **Local-Codex**.
Le lanceur suit le profil actif de `releases.json`. La premiere installation est
utilisable en candidat ; elle ne devient certifiee qu'apres `Certify -Promote`.

## Documentation locale et compatibilite

`Knowledge` ouvre le gestionnaire historique. Les commandes `openzim.ps1`,
`Start-OpenZimAssistant.ps1`, `Demarrer-OpenZim.cmd` et les taches periodiques
restent disponibles. `knowledge.legacyConfig` reference la configuration historique :
budget, chemins, sources, reprise `.part`, controles et inventaire sont reutilises.
Les anciens modeles et leurs branches de code ne sont pas supprimes.

## Mesures et certification

Les rapports sont dans `.local-codex/benchmark.json`, `certification.json` et
`runs/`. Le benchmark mesure un court prompt en streaming : chargement, TTFT,
tokens/s, RAM/VRAM et utilisation CPU/GPU echantillonnees, ainsi que `/api/ps`.
Ces pics concernent toute la machine. Un demarrage a froid et la saturation du
contexte ne sont pas garantis. Une mesure indisponible est `null`, pas zero.

La certification cree un petit projet Python comportant deux erreurs. Elle
demande a Hermes, via ACP, de chercher, lire, diagnostiquer, modifier deux fichiers,
utiliser le terminal, compiler, relancer les tests puis consulter OpenZIM. Le
controleur verifie aussi les fichiers et tests lui-meme. Les preuves d'outils
proviennent de la session SQLite native Hermes, lue sans modification : certaines
notifications ACP ne contiennent pas les resultats complets. Un seul controle
obligatoire en echec ou non execute interdit la promotion.

La certification couvre ce scenario assiste en plusieurs etapes. Elle ne garantit
ni la reussite de toute demande libre, ni l'interface graphique de VS Code, ni
une machine privee de reseau. L'absence d'outils web/delegation dans les traces
ne constitue pas un confinement reseau. Les permissions du client de test ne
sont pas une sandbox ; elles n'autorisent automatiquement que les patchs des
deux fichiers de la fixture.

## Mise a jour et retour arriere

Modifier explicitement la revision Hermes ou le modele du catalogue, puis :

```powershell
.\Local-Codex.ps1 -Action Update
.\Local-Codex.ps1 -Action Certify -Promote
.\Local-Codex.ps1 -Action Rollback
```

Hermes est installe a une revision Git precise avec son lockfile et les extras
ACP/MCP. Chaque modele/contexte/revision possede un profil distinct. Une nouvelle
configuration reste candidate tant que les controles echouent. `stable`,
`previous` et `candidate` sont conserves ; la promotion change atomiquement le
pointeur actif. Rollback reutilise les fichiers presents sans telecharger de modele.
Il refuse une configuration precedente manquante ou modifiee.

Ce rollback couvre les profils Hermes et la selection du modele. Il ne restaure
pas les binaires partages Ollama, OpenZIM ou VS Code. Ces composants ne sont pas
mis a jour implicitement. Leur mise a jour doit etre suivie d'un nouveau benchmark
et d'une certification. Les mises a jour ZIM restent gerees par Knowledge.

## Desactivation et donnees

`Uninstall` desactive le pointeur actif et conserve les composants, modeles, ZIM,
sessions et memoires. Ce n'est pas une desinstallation complete. Pour un retrait
complet, sauvegarder les donnees Hermes puis retirer manuellement l'entree
`acp.agents.Local-Codex` de VS Code et les composants devenus inutiles. Aucun
composant partage n'est supprime automatiquement.

Hermes conserve ses propres sessions, memoire et skills sous le profil indique
par `HERMES_HOME`. Local-Codex n'implemente pas de second systeme de memoire.
Les profils distincts ne migrent pas automatiquement leur historique. Les rapports
et configurations propres a la machine sont exclus de Git.

## Limites et travaux suivants

- Le catalogue contient un premier Qwen candidat ; les seuils materiels sont
  indicatifs. Le benchmark accepte plusieurs contextes mais ne choisit pas encore
  automatiquement entre plusieurs tailles, quantifications ou reglages KV cache.
- Le contexte 65536 est le candidat teste ici, pas une recommandation universelle.
- La delegation n'est pas imposee. Le champ materiel est indicatif et ne desactive
  pas a lui seul les outils natifs Hermes ; une politique native reste a valider.
- Aucun skill supplementaire n'est installe : les outils, sessions et skills
  natifs Hermes restent responsables du travail agentique.
- Les plateformes autres que Windows, les installations vierges, les GPUs AMD,
  les contextes longs et la restauration de versions partagees restent a tester.

## Sources techniques

Les sources officielles Hermes sont referencees dans
[l'audit de migration](Migration-LocalCodex.md). Les appels Ollama suivent
[Generate](https://docs.ollama.com/api/generate),
[Create](https://docs.ollama.com/api/create) et
[Running models](https://docs.ollama.com/api/ps).
Le modele initial est [Qwen 3.5 9B Q4_K_M](https://ollama.com/library/qwen3.5:9b-q4_K_M).

OpenZIM a effectivement fourni l'article **unittest — Unit testing framework**
dans `docs.python.org_en_all_2026-08.zim`, chemin
`docs.python.org/release/3.0/library/unittest.html`. Son apport concerne les notions
TestCase et assertions. Attention : cet article traite de Python 3.0 alors que le
runtime teste utilise Python 3.11 ; il ne valide pas les API modernes de Hermes.
La recherche locale Hermes/ACP n'a retourne aucun article pertinent.
