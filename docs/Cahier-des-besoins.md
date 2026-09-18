# Local-Codex - cahier des besoins

Ce document fixe la cible produit du depot. Local-Codex est un environnement
agentique de developpement local integre a Visual Studio Code. Ce n'est ni un
simple chatbot Ollama, ni un installateur Hermes, ni un gestionnaire Kiwix.

## Resultat utilisateur attendu

Apres une installation machine unique, un utilisateur doit pouvoir initialiser
n'importe quel projet, ouvrir le panneau Local-Codex dans VS Code et demander :

> Implemente cette fonctionnalite et verifie qu'elle fonctionne.

L'agent doit explorer, planifier, lire, modifier, executer, tester, diagnostiquer,
corriger, retester et resumer. Les actions, commandes, autorisations et diffs
doivent transiter par ACP et rester visibles dans VS Code.

## Contraintes incontournables

- Windows 10/11 64 bits en priorite.
- Inference locale avec Ollama et un seul modele Qwen de 9B maximum.
- Contexte agentique Hermes jamais inferieur a 64 000 tokens.
- ACP obligatoire pour l'experience VS Code ; un chatbot seul ne suffit pas.
- OpenZIM MCP et archives ZIM disponibles hors ligne apres installation.
- Installation machine separee de la configuration legere de chaque projet.
- Preservation des changements utilisateur et confirmation des actions sensibles.
- Validation independante du discours du modele avant tout statut READY.
- Mise a jour par candidat, certification, promotion explicite et rollback.
- Aucun projet utilisateur ne doit etre supprime par la desinstallation.

## Parcours normal

1. Installer Local-Codex.
2. Initialiser un projet.
3. Verifier Local-Codex.
4. Gerer la documentation locale.
5. Mettre a jour Local-Codex.
6. Consulter les parametres.
7. Desinstaller ou desactiver Local-Codex.

Les versions, chemins, benchmarks et erreurs brutes appartiennent au mode
avance. Le mode normal utilise principalement `[OK]`, `[INFO]`,
`[AVERTISSEMENT]` et `[ERREUR]`.

## Criteres de certification

Un profil n'est fonctionnel que si des controles independants prouvent :

- la liaison VS Code -> ACP -> Hermes ;
- le modele Qwen/Ollama avec le contexte requis ;
- recherche, lecture, planification et modification multi-fichiers ;
- terminal, observation d'un echec, correction et retest reussi ;
- streaming, activite des outils, autorisation et presentation des diffs ACP ;
- appel OpenZIM MCP et recuperation reelle d'une documentation locale ;
- absence de promotion si une preuve obligatoire manque.

## Priorites de decision

1. Fonctionnement agentique correct.
2. Fiabilite et qualite des modifications.
3. Integration VS Code et controle utilisateur.
4. Simplicite et confidentialite locale.
5. Performances et consommation de ressources.

Chaque evolution doit repondre a la question : rapproche-t-elle Local-Codex
d'une experience d'agent de developpement local simple et coherente dans VS Code ?
