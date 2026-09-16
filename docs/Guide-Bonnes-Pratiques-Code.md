# Référentiel de développement pour les agents IA locaux

Ce guide définit le socle commun à appliquer aux projets assistés par GPT-OSS,
Qwen ou un autre agent de développement. Il est volontairement indépendant du
langage. Les conventions natives du langage et les règles explicites du projet
restent prioritaires lorsqu'elles sont plus précises.

## 1. Ordre de priorité

Lorsqu'une règle semble contradictoire, appliquer cet ordre :

1. sécurité, intégrité des données et demande explicite de l'utilisateur ;
2. conventions et architecture déjà établies dans le projet ;
3. outils automatiques du projet : compilateur, formateur, linter et tests ;
4. conventions natives du langage ou du framework ;
5. présent référentiel général.

Ne pas modifier silencieusement une convention existante. Signaler le conflit
et proposer une migration séparée si une amélioration globale est souhaitable.

## 2. Méthode de travail obligatoire

Avant de coder :

- reformuler l'objectif et les critères d'acceptation ;
- inspecter les fichiers concernés et les conventions existantes ;
- distinguer faits, hypothèses et inconnues ;
- rechercher localement une API ou une syntaxe incertaine avec OpenZIM ;
- évaluer les risques : données, sécurité, compatibilité et régression ;
- préférer une modification limitée, réversible et vérifiable.

Pendant l'implémentation :

- conserver le comportement non concerné ;
- ne pas remplacer une modification utilisateur sans accord ;
- valider les entrées externes et traiter les erreurs à leur origine ;
- ajouter ou adapter les tests correspondant au changement ;
- mettre à jour la documentation touchée par le comportement.

Avant de terminer :

- exécuter les tests, le formateur et le linter disponibles ;
- vérifier qu'aucun secret, fichier temporaire ou débogage ne reste ;
- relire le diff et rechercher les effets secondaires ;
- annoncer clairement ce qui a changé, ce qui a été vérifié et les limites.

## 3. Principes de conception

Ordre de préférence : correction, lisibilité, simplicité, testabilité,
maintenabilité, sécurité, observabilité, puis optimisation mesurée.

- KISS : choisir la solution la plus simple qui satisfait le besoin.
- YAGNI : ne pas construire une extension hypothétique sans besoin actuel.
- DRY : supprimer la duplication d'une connaissance, pas toute ressemblance.
- Cohésion forte : regrouper ce qui change pour la même raison.
- Couplage faible : limiter les dépendances entre composants.
- SOLID est un ensemble d'heuristiques, pas une obligation d'ajouter des couches.
- Mesurer avant d'optimiser et mesurer à nouveau après optimisation.

## 4. Organisation d'un projet

La structure doit révéler l'intention. Exemple adaptable :

```text
project/
├── src/             code de production
├── tests/           tests unitaires et d'intégration
├── config/          configuration non secrète
├── scripts/         automatisations reproductibles
├── docs/            architecture et exploitation
├── README.md
└── .gitignore
```

Règles :

- éviter les fichiers fourre-tout et les dépendances circulaires ;
- séparer domaine, orchestration, interfaces et détails techniques lorsque la
  taille du projet le justifie ;
- centraliser les chemins et options configurables ;
- garder les secrets hors du code et de Git ;
- ne pas créer une arborescence complexe pour un petit script.

## 5. Conventions de nommage

Le nom doit exprimer l'intention et respecter d'abord l'usage du langage.

| Élément | Convention générale |
|---|---|
| Types, classes, composants | `PascalCase` lorsque le langage le prévoit |
| Fonctions et méthodes | verbe + objet ; casse native du langage |
| Variables | nom métier explicite ; casse native du langage |
| Booléens | préfixe `is`, `has`, `can`, `should` ou `enable` |
| Constantes | convention native, souvent `UPPER_SNAKE_CASE` |
| Collections | nom pluriel |
| Identifiants | suffixe explicite, par exemple `customerId` |
| Valeurs mesurées | unité dans le nom : `timeoutSeconds`, `sizeBytes` |
| Scripts PowerShell | `Verbe-Nom.ps1` avec un verbe PowerShell approuvé |

À éviter : `data`, `tmp`, `value2`, `manager`, `process` ou une abréviation non
évidente lorsqu'un nom métier plus précis est possible.

## 6. Fonctions, classes et modules

- une fonction possède une intention principale identifiable ;
- les effets de bord sont explicites et limités ;
- les dépendances importantes sont injectées ou passées en paramètres ;
- éviter les paramètres booléens ambigus et les longues listes de paramètres ;
- retourner des valeurs cohérentes ;
- déclarer une variable près de son utilisation, sauf configuration centralisée ;
- éviter l'état global mutable et les abstractions sans usage concret.

Les commentaires expliquent le pourquoi, une contrainte ou un compromis. Le
code et les noms expliquent le quoi. Documenter les interfaces publiques et les
comportements non évidents sans commenter chaque ligne.

## 7. Configuration, secrets et dépendances

Séparer strictement code, configuration et secrets.

- externaliser URLs, ports, chemins, timeouts et options d'environnement ;
- injecter les secrets par un mécanisme sécurisé ;
- ne jamais journaliser mot de passe, token, clé privée ou donnée personnelle
  inutile ;
- vérifier nécessité, maintenance, licence et sécurité avant une dépendance ;
- utiliser un fichier de verrouillage pour des builds reproductibles ;
- demander confirmation avant toute installation ou modification système
  importante ;
- utiliser uniquement des sources de paquets fiables.

## 8. Validation, erreurs et ressources

Toute entrée externe est non fiable jusqu'à validation : type, format, taille,
plage, encodage, autorisation et cohérence métier.

Une erreur doit être détectée, contextualisée, propagée ou traitée, puis rendue
observable. Ne jamais utiliser une capture vide. Préserver la cause originale et
capturer uniquement les exceptions que le code sait réellement traiter.

Toute ressource acquise doit être libérée avec le mécanisme natif approprié :
`using`, `with`, `try/finally`, `defer`, RAII ou équivalent.

## 9. Données, fichiers et concurrence

- traiter les gros volumes par streaming, pagination ou lots bornés ;
- compter entrées, sorties, rejets et doublons dans les pipelines importants ;
- écrire dans un fichier temporaire, valider, puis publier atomiquement ;
- protéger les traitements non réentrants avec un verrou système fiable ;
- rendre idempotentes les opérations susceptibles d'être rejouées ;
- utiliser des retries limités uniquement pour les erreurs transitoires, avec
  délai et idéalement backoff ;
- définir un timeout pour tout appel distant.

## 10. Journalisation et observabilité

Utiliser des événements explicites et recherchables, idéalement structurés :

```text
timestamp level component event duration_ms result correlation_id
```

Niveaux : `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`. Les noms d'événements
peuvent utiliser `snake_case`, par exemple `download_completed`.

Pour un service, distinguer logs, métriques, traces et état de santé. Les logs
doivent permettre de diagnostiquer sans exposer de secret.

## 11. Tests et débogage

Tester les comportements et risques importants plutôt que poursuivre un chiffre
de couverture isolé.

- tests unitaires rapides et déterministes ;
- tests d'intégration sur les frontières réelles importantes ;
- tests de bout en bout réservés aux parcours critiques ;
- test de régression pour chaque bug significatif lorsque possible ;
- aucun test ne dépend inutilement du réseau ou de l'heure réelle.

Procédure de débogage : reproduire, réduire, collecter les faits, formuler une
hypothèse, la tester, identifier la cause racine, corriger, ajouter un test de
régression, puis vérifier les effets secondaires.

## 12. Sécurité

- appliquer le moindre privilège ;
- paramétrer les requêtes SQL ;
- encoder ou échapper selon le contexte de sortie ;
- distinguer authentification et autorisation ;
- refuser par défaut lorsqu'une vérification de sécurité échoue ;
- protéger les opérations destructives par confirmation et cible exacte ;
- maintenir les dépendances et analyser leurs vulnérabilités ;
- ne jamais fabriquer un mécanisme cryptographique maison.

Les mots de passe doivent généralement être hachés avec un algorithme adapté,
pas chiffrés de manière réversible.

## 13. Git, revue et automatisation

- un commit correspond à une intention cohérente et testable ;
- ne pas mélanger refactoring général et correction fonctionnelle ;
- relire le diff avant commit ;
- automatiser formatage, lint, analyse statique, tests et contrôles de sécurité ;
- documenter migration, compatibilité et retour arrière lorsque nécessaire ;
- revoir le code, pas la personne.

Pipeline indicatif :

```text
format → lint → analyse statique → tests → build → sécurité → package
```

## 14. Définition de terminé

Un changement est terminé lorsque :

- le comportement demandé fonctionne ;
- les conventions du projet sont respectées ;
- les entrées et erreurs pertinentes sont traitées ;
- les tests utiles passent ;
- le code temporaire et les secrets sont absents ;
- la documentation touchée est à jour ;
- le changement reste limité à son objectif ;
- les limites ou vérifications non réalisées sont annoncées.

## 15. Règles spécifiques à l'agent IA

L'agent doit :

1. inspecter avant de modifier ;
2. consulter OpenZIM lorsqu'une information technique est incertaine ;
3. ne jamais inventer une API, une option ou un résultat de test ;
4. préserver les changements existants de l'utilisateur ;
5. demander confirmation avant une suppression ou une action irréversible ;
6. produire le plus petit changement cohérent ;
7. tester proportionnellement au risque ;
8. expliquer toute dérogation au présent guide ;
9. terminer par un résumé des changements et validations.

## Origine et adaptation

Ce référentiel est une synthèse adaptée des deux documents fournis par
l'utilisateur. Certaines formulations trop absolues ont été rendues
contextuelles : les variables sont déclarées près de leur usage, les tests sont
orientés risque, les dépendances ne sont pas installées sans consentement et les
conventions natives du langage restent prioritaires.

