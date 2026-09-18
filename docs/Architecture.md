# Architecture de Local-Codex

Local-Codex separe les decisions produit des composants techniques externes.
Cette frontiere permet de tester la logique sans telecharger un modele, modifier
VS Code ou appeler le planificateur de taches.

```text
ENTREE ET EXPERIENCE
Local-Codex.ps1, UserExperience.psm1
        |
        v
CAS D USAGE
Project, Knowledge, Models, Benchmark, Certification, Updates
        |
        v
ADAPTATEURS EXTERNES
Prerequisites, Hermes, OpenZim, Hardware
        |
        v
Git, VS Code/ACP, Ollama/Qwen, uv/Python isole, OpenZIM MCP, Windows
```

## Regles de dependance

- Le menu orchestre les cas d'usage mais ne reimplemente pas les integrations.
- Les commandes systeme sont centralisees dans des adaptateurs testables.
- La configuration JSON constitue la source de verite des choix modifiables.
- Les modules metier ne doivent pas dependre de la presentation terminal.
- Les ecritures importantes sont atomiques ou protegees par un verrou.
- Les migrations conservent un chemin explicite depuis l'ancienne version.
- Les erreurs externes sont traduites en messages exploitables sans etre masquees.

## Strategie de changement

Une evolution commence par le plus petit parcours vertical verifiable. Elle
ajoute ensuite les variantes seulement apres retour d'usage. Les abstractions
sont introduites lorsqu'elles isolent une dependance instable ou suppriment une
duplication de connaissance, pas pour anticiper des besoins hypothetique.

## Strategie de test

- tests unitaires hors reseau pour les decisions, formats et invariants ;
- tests d'integration pour les adaptateurs locaux ;
- certification ACP de bout en bout pour le parcours critique ;
- promotion interdite si une preuve obligatoire manque ;
- rollback conserve tant que le nouveau candidat n'est pas certifie.

## Design de l'experience

Le mode normal presente uniquement l'etat, l'impact et la prochaine action. Le
mode avance expose versions, chemins, contexte, mesures et erreurs brutes. Une
operation longue ou destructive annonce sa cible et demande confirmation. Les
messages emploient les etats `[OK]`, `[INFO]`, `[AVERTISSEMENT]` et `[ERREUR]`.
