---
description: Rapport de préparation d'une feature avant merge (lecture seule, advisory, ne bloque jamais). Accepte un FEAT-ID ; à défaut, le déduit de la branche courante.
argument-hint: FEAT-051 | 051 (défaut : déduit de la branche courante)
---

Génère le rapport de readiness d'une feature. **Lecture seule** : ne modifie
aucun fichier du dépôt, ne déploie rien, n'exécute pas les tests.

## Argument

$ARGUMENTS (défaut : déduit de la branche courante)

## Étapes

1. **Résoudre le FEAT-ID**
   - Si `$ARGUMENTS` contient un identifiant (`051`, `FEAT-051`) → l'utiliser.
   - Sinon, le déduire de la branche : `git branch --show-current` sur
     `feature/051-...` → `051`.
   - Si aucun ID n'est déductible → demander à l'utilisateur, ne pas deviner.

2. **Lancer le script** (c'est lui qui produit le score, pas toi) :

   ```bash
   dart run tool/feature_ready.dart <FEAT-ID>
   ```

   Ajoute `--no-analyze` si l'utilisateur veut un résultat rapide sans
   `flutter analyze` / `dart format` (le poids « Santé technique » est alors
   redistribué sur les autres catégories).

   ⚠️ Sur un clone frais, `flutter analyze` échoue tant que le codegen n'a pas
   tourné (`dart run build_runner build --delete-conflicting-outputs`) : la
   catégorie « Santé technique » sortirait à ❌ pour rien. Lance le codegen
   avant, ou passe `--no-analyze`.

3. **Afficher le rapport markdown tel quel.** Ne recalcule pas le score,
   ne réécris pas les catégories : le rapport doit rester déterministe et
   reproductible d'un run à l'autre.

4. **Commenter, sans gonfler le score** : après le rapport, tu peux ajouter
   une courte lecture des points manquants et proposer les actions concrètes
   (écrire les tests widget manquants, mettre à jour `docs/state/FEATURES.md`…).
   Distingue bien ce qui vient du script de ton propre avis.

## Ce que la commande ne fait PAS

- Elle **ne bloque pas** : le script sort toujours en 0 (sauf `--strict`, opt-in
  manuel — la CI ne l'utilise pas).
- Elle **ne remplace ni `code-reviewer` ni `qa-tester`**. Les catégories
  « Accessibilité » et « Complétude produit » ne sont qu'un accusé de réception
  documentaire : elles vérifient que le plan traite le sujet, pas que le code
  est réellement accessible ou complet.
- Elle **n'écrit pas le rapport dans le dépôt**. Pour l'archiver hors dépôt :
  `dart run tool/feature_ready.dart 051 > /tmp/readiness-051.md`

## Quand l'utiliser

- Avant d'ouvrir une PR, pour voir ce qui manque encore.
- Après `qa-tester`, comme checklist finale de Definition of Done
  (cf. `CLAUDE.md`).
