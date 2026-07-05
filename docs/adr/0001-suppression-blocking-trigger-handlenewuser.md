# ADR 0001 — Suppression du blocking trigger `handleNewUser`

- **Statut** : accepté (appliqué sur `feature/anon-auth-m1` le 2026-07-05 ; décision initiale 2026-07-02)
- **Contexte technique** : Firebase Cloud Functions (Node 20), projet `easy-rent-54cd4`

## Contexte

`functions/src/auth/handle_new_user.ts` définissait un trigger **`beforeUserCreated`**
(fonction bloquante Identity Platform) censé provisionner le document
`landlords/{uid}` à la création d'un compte.

Problème : les blocking functions (`beforeUserCreated` / `beforeUserSignedIn`)
exigent **Identity Platform (GCIP)** activé sur le projet. GCIP n'est **pas**
activé (et ne le sera pas sans besoin serveur avéré). En conséquence,
`firebase deploy --only functions` **échoue systématiquement (exit 2)** :
impossible de déployer la moindre mise à jour de fonction tant que ce trigger
est déclaré. Le trigger n'a donc **jamais tourné** en production — c'est du
code mort qui bloque tout le déploiement functions.

## Décision

**Retirer `handleNewUser`** (fichier + export dans `index.ts` + test).

Le provisioning du doc `landlords/{uid}` est assuré **100 % côté client**
(`lib/features/auth/data/auth_repository.dart` : `signUpWithPassword`,
`signInWithGoogle/Apple`, `signInAnonymously`), avec les **Firestore Security
Rules** comme garde-fou du payload (`match /landlords/{uid}`). La promotion
anonyme→compte passe par la callable `finalizeAnonymousUpgrade` (client-driven,
retry-friendly).

## Conséquences

- ✅ `firebase deploy --only functions` redevient déployable (exit 0) — prérequis
  pour toute évolution future (ex. notification support par CF, archivage de
  l'avis de régularisation FEAT-029 V2 via une catégorie `documents` supplémentaire).
- ⚠️ **Ne PAS réintroduire de blocking function** (`beforeUserCreated`, etc.)
  sans réactiver GCIP au préalable et réévaluer cet ADR.
- Build de déploiement : `tsc -p tsconfig.build.json` (exclut `src/__tests__` et
  `*.test.ts` du bundle `lib/` livré) — évite d'embarquer les tests (dépendance
  `vitest`, devDep) dans l'artefact déployé.
