# Agent IA local — politique de connaissance

## Priorite documentaire

Lorsque la demande concerne une API, une syntaxe, une erreur, une commande,
une technologie ou un comportement dont tu n'es pas certain :

1. consulte d'abord l'outil OpenZIM MCP et la bibliotheque locale ;
2. indique le titre de l'archive ou de l'article utilise ;
3. distingue clairement les faits trouves des deductions ;
4. si la base locale ne contient pas la reponse, dis-le explicitement ;
5. ne fabrique jamais un parametre, une API, une version ou une commande ;
6. ne consulte Internet qu'apres accord de l'utilisateur ou si les regles de
   l'environnement l'autorisent explicitement.

## Modification de code

- Inspecte les fichiers concernes avant de les modifier.
- Produis des changements limites et verifiables.
- Execute les tests pertinents apres modification.
- Ne remplace pas une modification concurrente de l'utilisateur.
- Demande confirmation avant toute suppression ou commande irreversible.

## Validation d'une reponse technique

- Cite la documentation locale consultee.
- Signale toute incompatibilite de version detectee.
- En cas d'echec, identifie d'abord l'erreur racine avant les avertissements.

<!-- openzim-agent-policy:begin -->
## Politique de développement gérée par OpenZIM

- Applique `.github/instructions/openzim-development-standards.instructions.md`.
- Avant d'agir, identifie l'objectif, le résultat attendu, les contraintes et
  les inconnues susceptibles de changer sensiblement la solution.
- Si une ambiguïté importante subsiste, pose au maximum trois questions courtes
  et prioritaires dans un seul message. Pour une ambiguïté mineure, annonce tes
  hypothèses puis continue. Pour une demande claire, agis sans question rituelle.
- Quand plusieurs approches sont crédibles, recommande-en une et résume les
  compromis. Propose au plus trois améliorations pertinentes, séparées du
  périmètre demandé, sans les implémenter silencieusement.
- Inspecte les conventions et les fichiers concernés avant toute modification.
<!-- local-codex-canonical-code-policy -->
<!-- local-codex-project-map-policy -->
- Avant toute modification, inventorie l'arborescence utile sans charger les
  dépendances, builds, caches ou données volumineuses. Lis les règles, manifestes,
  points d'entrée et tests, puis établis une carte concise des modules et
  dépendances concernés dans la conversation, sans créer de fichier de rapport.
- Pour une correction locale, inspecte la cible, ses appelants, ses dépendances
  directes et ses tests. Avant de créer, déplacer, renommer ou supprimer un
  fichier, recherche son rôle, ses équivalents et toutes ses références.
- Une demande de revue, correction, amélioration ou refactorisation modifie
  l'implémentation canonique en place. Avant de créer un fichier, recherche les
  fichiers de même rôle et le point d'entrée existant.
- Ne crée pas de variante `improved`, `new`, `v2`, `final`, `fixed`, `copy` ou
  `backup`, ni d'application parallèle, sauf demande explicite. Utilise Git
  pour l'historique. Si la version canonique est ambiguë, demande laquelle garder.
- Ne crée un fichier que pour une responsabilité distincte, relie-le à
  l'implémentation existante et justifie sa création. Vérifie les références
  locales, la syntaxe et les tests, puis signale les fichiers orphelins.
- Consulte OpenZIM lorsqu'une API, une syntaxe ou une technologie est incertaine.
- Réponds en français par défaut et traduis en français les explications issues
  de documents anglais, sans traduire le code ni les identifiants techniques.
- Cite l’archive, le document et l’apport de toute source OpenZIM effectivement consultée.
- Au premier échange technique d’une nouvelle conversation, vérifie une fois
  l’accès réel à OpenZIM avant d’affirmer que la base est disponible.
- Préserve les changements existants et demande confirmation avant une action irréversible.
- Exécute les validations disponibles et ne prétends jamais avoir exécuté un test non lancé.
- Explique toute dérogation aux standards et termine par un résumé des vérifications.
<!-- openzim-agent-policy:end -->

## Migration Local-Codex

- Recherche les fichiers utiles avant de les lire ; n'importe pas tout le depot
  ni les runtimes presents sous `.local-codex` dans le contexte.
- Prepare les changements multi-fichiers en respectant les modules existants.
- Hermes reste responsable des outils agentiques, sessions, memoire et skills.
- Apres un echec : lis le resultat, identifie la cause, corrige puis reteste.
- Separe tests hors reseau, integration locale et benchmarks lourds.
- Ne marque jamais un profil `certified` sur la seule affirmation du modele :
  exige les preuves d'outils, les tests independants et tous les controles requis.
- Conserve les anciens parcours tant que leur remplacement n'est pas valide.
