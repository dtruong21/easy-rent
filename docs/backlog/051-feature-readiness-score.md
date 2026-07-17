# FEAT-051 — Feature Readiness Score

> Plan technique : [`docs/plans/FEAT-051-feature-readiness-score.md`](../plans/FEAT-051-feature-readiness-score.md)
>
> **Note d'ID** : le plan initial portait `FEAT-045`, déjà pris par
> « Suppression compte in-app » (✅ done, PR #69). Renuméroté en `FEAT-051`.

## User story

**En tant que** développeur (ou agent Claude),
**je veux** un rapport de préparation avant merge,
**afin de** savoir précisément ce qui manque encore à une feature.

## Problème

La Definition of Done de `CLAUDE.md` est vérifiée à la main, feature par
feature. Les oublis récurrents : tests widget, mise à jour de `docs/state/`,
parité des clés ARB. Rien ne les rend visibles avant la revue.

## Périmètre

Une commande `/feature-ready [FEAT-ID]` qui affiche un rapport markdown noté
sur 100, réparti en 7 catégories pondérées (documentation 15, tests 25,
localisation 10, accessibilité 10, complétude produit 15, santé technique 15,
état projet 10).

## Critères d'acceptation

- [x] Une commande de readiness existe (`/feature-ready`).
- [x] Un rapport markdown est produit (stdout).
- [x] Chaque catégorie contribue au score total.
- [x] Les points manquants sont listés explicitement.
- [x] Le rapport est déterministe : deux exécutions sans changement de code
      produisent un résultat identique à l'octet près (aucun timestamp,
      collections triées) — couvert par `test/unit/feature_ready_test.dart`.
- [x] La feature ne modifie aucun fichier du dépôt (rapport sur stdout).
- [x] Non bloquant : code de sortie 0 par défaut, la CI n'est pas touchée.

## Hors scope

- Déployer l'application.
- Exécuter les tests automatiquement (le script lit, il ne lance pas
  `flutter test`).
- Remplacer `code-reviewer` ou `qa-tester` — le score est *advisory*.

## Limites connues

Les catégories **Accessibilité** et **Complétude produit** ne sont qu'un accusé
de réception documentaire : le script vérifie que le plan traite le sujet, pas
que le code est réellement accessible. Le rapport le dit explicitement.

« Santé technique » lance `flutter analyze`, qui remonte ~1994 erreurs sur un
clone frais tant que `dart run build_runner build` n'a pas généré les fichiers
`.freezed.dart`/`.g.dart` — d'où un ❌ trompeur. Lancer le codegen avant, ou
utiliser `--no-analyze` (le poids est alors redistribué).

Le score est **uniforme** : une feature d'outillage sans UI (comme FEAT-051
elle-même) est pénalisée sur « tests widget » et créditée à tort sur
« accessibilité » — le plan cite les mots « accessibilité » et « clavier » dans
son propre énoncé de catégories, ce qui suffit à valider le check. Vérifié :
FEAT-051 sort à 85/100 avec `--no-analyze`, dont un ✅ a11y non mérité. À
traiter si le besoin se confirme (catégories N/A déclarées par le plan).

L'association tests → feature repose sur la convention maison « un test cite son
`FEAT-XXX` en commentaire » (vérifiée : 25 occurrences pour FEAT-043, 9 pour
FEAT-045). Un test qui ne cite pas son ID est invisible pour le script.

## Extensions futures

Store Release Readiness, Performance Readiness, Security Readiness, SEO
Readiness.
