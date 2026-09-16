---
name: 'OpenZIM Development Standards'
description: 'Standards communs de conception, nommage, sécurité, tests et documentation.'
applyTo: '**'
---

<!-- openzim-standards:begin -->
# Standards de développement obligatoires

## Priorité et adaptation

- Respecte d'abord la demande explicite, la sécurité, les conventions existantes du projet et les outils automatiques du langage.
- Applique ensuite ces standards généraux. Ne remplace pas une convention existante silencieusement.
- Si une dérogation est nécessaire, explique-la brièvement et limite sa portée.

## Avant toute modification

- Reformule l'objectif et identifie les critères d'acceptation.
- Inspecte les fichiers concernés, l'architecture, les tests et les conventions existantes.
- Distingue les faits, les hypothèses et les inconnues.
- Consulte OpenZIM avec `openzim_search` ou `openzim_search_archive` pour toute
  API, syntaxe ou technologie incertaine.
- Choisis le plus petit changement cohérent, réversible et vérifiable.

## Code et architecture

- Préfère correction, lisibilité et simplicité à la sophistication.
- Applique KISS et YAGNI. Utilise DRY pour une connaissance réellement commune, pas pour toute ressemblance.
- Donne une responsabilité principale à chaque fonction ou module.
- Limite les effets de bord, l'état global mutable, le couplage et les dépendances inutiles.
- Respecte les conventions natives du langage et du framework.
- Utilise des noms métier explicites : verbes pour les actions, pluriel pour les collections, unités dans les mesures.
- Pour PowerShell, nomme scripts et fonctions avec `Verbe-Nom`.
- Explique le pourquoi dans les commentaires ; laisse le code et les noms expliquer le quoi.

## Données, erreurs et sécurité

- Valide toute entrée externe : type, format, taille, plage, autorisation et cohérence.
- Ne masque jamais une exception. Ajoute du contexte et préserve la cause originale.
- Libère systématiquement fichiers, connexions, verrous, processus et fichiers temporaires.
- Pour les gros volumes, préfère streaming, pagination ou lots bornés.
- Pour un fichier important : écrire dans un temporaire, valider, puis publier atomiquement.
- Sépare code, configuration et secrets. Ne versionne et ne journalise jamais un secret.
- Demande confirmation avant une suppression, installation ou action irréversible.

## Fiabilité et observabilité

- Ajoute des timeouts aux appels distants et limite les retries aux erreurs transitoires.
- Rends idempotentes les opérations susceptibles d'être rejouées.
- Empêche les exécutions parallèles lorsque les ressources partagées l'exigent.
- Utilise des logs contextualisés avec niveaux et événements stables en `snake_case`.

## Tests et livraison

- Teste les comportements et risques importants ; ajoute un test de régression pour un bug significatif.
- Exécute les tests, le formateur, le linter et l'analyse statique disponibles.
- Ne prétends jamais avoir exécuté une validation qui ne l'a pas été.
- Relis le diff, vérifie les effets secondaires et mets à jour la documentation concernée.
- Termine par un résumé des changements, tests exécutés et limites restantes.

Le guide complet du projet est disponible dans `docs/ai/Guide-Bonnes-Pratiques-Code.md`.
<!-- openzim-standards:end -->
