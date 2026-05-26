---
description: Rafraîchit le cache d'état du projet (docs/state/*). À lancer quand l'état est périmé ou après un gros refactor.
argument-hint: all | schema | routes | features | deps | functions (défaut: all)
---

Invoque l'agent `state-keeper` avec le scope donné en argument.

## Argument

$ARGUMENTS (défaut : `all`)

## Étapes

1. Invoke `state-keeper` avec instruction : "refresh: $ARGUMENTS"
2. Affiche le résumé renvoyé par l'agent
3. Si des incohérences sont détectées → liste-les à l'utilisateur et propose des actions

## Quand l'utilisateur doit-il lancer ça ?

- **Après un sprint** : `/refresh-state all` pour repartir propre
- **Après une migration** : `/refresh-state schema`
- **Après ajout de routes** : `/refresh-state routes`
- **Si un agent flag un état périmé** : refresh ce qu'il demande
- **Jamais** à chaque session — c'est justement ce qu'on veut éviter

## Note importante

Le but de cette commande est de **payer le coût du scan UNE FOIS** plutôt qu'à chaque session. Si tu es en train de la lancer à chaque démarrage, quelque chose ne va pas dans le workflow — re-lis `docs/AGENTS.md`.
