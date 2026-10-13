# FEAT-046 — Purge différée des quittances archivées (cron RGPD) — Design

> **Statut** : Design validé (brainstorm 2026-09-15). Prêt pour `writing-plans`.
> **Feature** : FEAT-046 « Purge différée des quittances archivées » (RGPD art. 5.1.e — limitation de la conservation).
> **Domaine** : payments-receipts (collection `receipts`) — back-end pur (Cloud Function planifiée).
> **Dépend de** : FEAT-045 (`deleteAccount` + `stampRetainedReceipts`) ✅ — l'enabler qui pose déjà `retentionUntil`.

## Problème

À la suppression d'un compte (FEAT-045), les quittances (`receipts`) ne sont pas effacées : la loi impose une conservation (valeur probante, loi du 6 juillet 1989 ; le code retient 5 ans). `deleteAccount` les **conserve** et pose sur chacune deux champs : `accountDeletedAt` (traçabilité) et `retentionUntil` (= date de suppression + 5 ans), via `stampRetainedReceipts` (`functions/src/callable/delete_account.ts`).

Le commentaire de cette fonction annonce explicitement « échéance de purge pour un **futur cron** ». Ce cron n'existe pas. Résultat : les quittances d'un compte supprimé resteraient indéfiniment dans Firestore, en violation de la **limitation de la conservation** (RGPD art. 5.1.e) et de la promesse de la politique de confidentialité v1.2 (« puis supprimées à l'échéance »).

FEAT-046 livre ce cron.

## Périmètre

### Inclus (V1)

- Une **Cloud Function planifiée** `purgeExpiredReceipts` qui, chaque jour, **hard-delete** les documents `receipts` dont `retentionUntil <= now`.
- Exécution quotidienne à **03:00 Europe/Paris**, region `europe-west1` (calquée sur `cleanupExpiredAnon`).
- Suppression paginée et bornée par run (voir Composant), idempotente et sûre en cas de run partiel.
- Tests unitaires (vitest + `FakeFirestore`).

### Exclus (hors périmètre)

- **Nettoyage Storage** : les quittances n'ont **aucun objet Storage côté serveur**. Le PDF est généré **client-side** (FEAT-007/008, `pdf` + `share_plus`) ; le champ `pdfPath` du modèle Dart n'est **jamais écrit** par une Cloud Function (`generateReceipt` ne le pose pas), et `deleteAccount` ne purge le Storage que sous `documents/{uid}/**`. Il n'existe donc pas de contrat « PDF de quittance en Storage » à honorer. Aucune suppression Storage dans ce cron.
- **Purge pour un autre motif** que l'échéance de rétention post-suppression de compte : `retentionUntil` n'est posé QUE par `stampRetainedReceipts`. On ne crée aucune autre voie de purge (YAGNI).
- **Anonymisation partielle / soft-delete** : à l'échéance, la conservation légale a expiré ; la quittance est **supprimée**, pas anonymisée.
- **Anti-doublon / verrou distribué** : inutile — l'opération est idempotente (supprimer un doc déjà parti est un no-op) et le cron est mono-instance quotidien.

## Décision d'architecture

**Cron sur la base `(default)`, `admin.firestore()` direct.** Les fonctions planifiées et les triggers sont l'exception documentée à l'isolation ADR 0003 (CLAUDE.md : « crons et triggers exceptés, volontairement sur `(default)` ») : elles n'ont pas de `request` porteur d'Origin, donc pas de `dbForRequest`. `purgeExpiredReceipts` suit exactement le patron de `cleanupExpiredAnon` / `reconcileEntitlements` (`functions/src/scheduled/`). **Conséquence assumée** : le cron n'agit que sur la base de production `(default)` ; les quittances de la base `staging` ne sont pas purgées par ce cron — cohérent avec les deux crons existants et sans enjeu (staging n'a pas de données de production à protéger au titre du RGPD).

## Composant

### `purgeExpiredReceipts` — `functions/src/scheduled/purge_expired_receipts.ts`

Signature (patron `onSchedule` v2, identique à `cleanupExpiredAnon`) :

```ts
export const purgeExpiredReceipts = onSchedule(
  {schedule: "0 3 * * *", timeZone: "Europe/Paris", region: "europe-west1"},
  async () => { ... },
);
```

Algorithme :

1. `now = admin.firestore.Timestamp.now()`.
2. Boucle, jusqu'à un plafond de sécurité `MAX_DELETES_PER_RUN` (par ex. 2000, soit 5 pages de 400 — large devant tout volume réaliste d'expirations un même jour) :
   a. Requête `db.collection("receipts").where("retentionUntil", "<=", now).limit(PAGE_SIZE)` (PAGE_SIZE = 400, aligné sur `PURGE_PAGE_SIZE` de `delete_account.ts`).
   b. Si vide → sortie de boucle.
   c. Hard-delete les docs de la page dans un `WriteBatch` (`batch.delete(doc.ref)` puis `batch.commit()`). Les docs supprimés sortent des pages suivantes (pas de curseur nécessaire — même patron que `purgeCollectionByLandlord`).
   d. Incrémente le compteur ; si le plafond est atteint, sortir (le reste sera traité le lendemain — l'horizon est de 5 ans, un jour de délai supplémentaire est sans impact).
3. `logger.info` du nombre total supprimé (`purgeExpiredReceipts: purged N expired receipts`), ou un `info` « rien à purger » si zéro (patron `cleanupExpiredAnon`).

**Sécurité de la requête** : seules les quittances d'un **compte supprimé** portent `retentionUntil` (posé uniquement par `stampRetainedReceipts`). Les quittances d'un compte **actif** n'ont pas ce champ et **ne sont jamais retournées** par `where("retentionUntil", "<=", now)` (Firestore n'indexe pas les documents sans le champ dans un index mono-champ, et un `<=` ne matche pas un champ absent). Aucun risque de supprimer une quittance d'un compte vivant.

**Index** : requête d'inégalité sur un **seul** champ (`retentionUntil`) → couverte par l'**index mono-champ automatique** de Firestore. Aucun index composite à déclarer (à confirmer au premier build/déploiement ; si Firestore réclamait un index, l'ajouter à `firestore.indexes.json`, déployé par la CI).

**Export** : ajouter `purgeExpiredReceipts` aux exports de `functions/src/index.ts` (à côté des autres scheduled).

## Données disponibles (vérifié dans le code)

- `receipts.retentionUntil : Timestamp` — posé par `stampRetainedReceipts` (`delete_account.ts:150`), = `now + RECEIPT_RETENTION_MS` (5 ans).
- `receipts.accountDeletedAt` — posé conjointement (traçabilité ; non requis par la requête de purge).
- `PURGE_PAGE_SIZE = 400` dans `delete_account.ts` (référence de taille de page).
- Patron cron : `functions/src/scheduled/cleanup_expired_anon.ts` (schedule, timeZone, region, `admin.firestore()`, batch borné, logs).

## Gestion d'erreur

- Un `batch.commit()` qui échoue laisse remonter l'erreur (le run échoue, Cloud Scheduler re-déclenchera le lendemain ; les docs non supprimés seront repris — idempotent). Pas de `try/catch` masquant : un échec doit être visible dans les logs/alertes.
- Aucun état partagé, aucune ressource externe : pas de rollback à gérer.

## Tests

`functions/src/__tests__/purge_expired_receipts.test.ts` (vitest + `FakeFirestore`, patron des tests scheduled/documents existants) :

1. **Purge les quittances expirées** : deux receipts avec `retentionUntil` dans le passé → toutes deux supprimées ; le retour/observable (docs restants dans `FakeFirestore`) est vide.
2. **Épargne les `retentionUntil` futurs** : un receipt avec `retentionUntil` dans le futur → conservé.
3. **Épargne les receipts sans `retentionUntil`** (compte actif) : un receipt sans le champ → jamais supprimé.
4. **Pagination** : semer > PAGE_SIZE receipts expirés (ou réduire PAGE_SIZE de test) et vérifier que tous sont purgés sur un run (boucle multi-batch).
5. **Aucune donnée** : collection vide → run sans erreur, log « rien à purger ».

> Le `FakeFirestore` doit supporter `where("<=")` sur Timestamp + `batch.delete` + `limit` (déjà utilisés ailleurs ; à confirmer au moment de l'implémentation, sinon étendre le fake comme pour les autres scheduled).

## Definition of Done (docs d'état)

`state-keeper` ciblé :
- `docs/state/functions/payments-receipts.md` (ou le shard functions du domaine) : ajouter la scheduled `purgeExpiredReceipts` ; incrémenter le décompte des scheduled (2 → 3).
- `docs/state/FEATURES.md` : FEAT-046 → ✅ done.
- `docs/state/CHANGELOG.md` : entrée FEAT-046.
- `docs/state/INDEX.md` : décompte scheduled (« 2 scheduled » → « 3 scheduled »).

Aucune Rules touchée. Index : normalement aucun (mono-champ auto) ; si le déploiement en réclame un, il part par la CI (`develop` → base `staging`, `main` → `(default)`). **Cloud Functions : déploiement manuel** délibéré après merge (le cron doit être déployé pour s'exécuter).

## Légal / conformité

- **RGPD art. 5.1.e** (limitation de la conservation) : la purge à échéance est l'exécution concrète de cette obligation. L'échéance (5 ans) matérialise l'équilibre entre la valeur probante (loi 1989) et le droit à l'effacement.
- **Politique de confidentialité v1.2** : honore la promesse « conservées 5 ans puis supprimées à l'échéance ».
- **Irréversibilité assumée** : à l'échéance, la conservation légale a expiré ; le hard-delete est le comportement voulu (pas d'anonymisation, pas de corbeille).

## Hors scope / suites possibles

- Alerte/metric sur volume purgé (observabilité) — non nécessaire au vu du volume.
- Purge des quittances `isVoided` anciennes indépendamment d'une suppression de compte — non demandé, pas de base légale pour raccourcir la rétention d'un compte actif.
