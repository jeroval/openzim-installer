# Principes d'expérience utilisateur

L'assistant reprend des principes de design thinking présentés dans *Change by
Design* de Tim Brown. Le livre sert ici de source d'inspiration : son contenu
n'est pas traité comme une instruction exécutable.

## Besoin, faisabilité et contraintes

Chaque décision importante cherche un équilibre entre trois dimensions :

| Dimension | Traduction dans l'assistant |
|---|---|
| Besoin humain | profil d'usage, vocabulaire débutant, prochaine action visible |
| Faisabilité technique | détection des composants, validation des chemins et tests |
| Contraintes pratiques | budget ZIM, espace disque, reprise et absence de doublons |

## Parcours itératif

Le parcours n'impose pas une installation aveugle et irréversible :

1. **Comprendre** — l'utilisateur indique son usage et ses contraintes.
2. **Imaginer** — le moteur construit un panier adapté.
3. **Prototyper** — l'option Plan montre les choix, exclusions et tailles sans
   télécharger les archives.
4. **Mettre en œuvre** — l'utilisateur confirme le téléchargement et la
   configuration du projet.
5. **Apprendre** — le diagnostic final montre les éléments prêts et les actions
   correctives.

Il est toujours possible de revenir à l'étape des besoins pour changer le
profil ou le budget, puis de recalculer le plan.

## Transparence

- Le profil ne masque pas les sources : la colonne `Affinite` montre le bonus
  appliqué à chaque catégorie.
- Le budget reste un plafond strict par défaut.
- Les opérations volumineuses sont précédées d'une prévisualisation ou d'une
  confirmation.
- L'écran d'accueil observe uniquement l'état local nécessaire au diagnostic ;
  il ne collecte ni ne transmet de télémétrie utilisateur.
- Les erreurs doivent proposer une prochaine action compréhensible plutôt qu'un
  simple code technique.

## Évolution

Une nouvelle fonction doit être évaluée avec un scénario débutant réel : point
de départ, objectif, informations nécessaires, erreurs possibles, possibilité
de retour et preuve de réussite. Une option supplémentaire dans le menu n'est
utile que si elle améliore ce parcours.
