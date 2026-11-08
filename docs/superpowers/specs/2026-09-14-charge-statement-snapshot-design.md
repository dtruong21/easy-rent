# FEAT-033 — Décompte de régularisation figé (snapshot immuable) — Design

> **Statut** : Design validé (brainstorm 2026-09-14). Prêt pour `writing-plans`.
> **Feature** : FEAT-033 (jusqu'ici `💡 idea` dans `docs/state/FEATURES.md`).
> **Domaine** : leases / charge_regularization (+ expenses-documents, account pour l'export RGPD).
> **Dépend de** : FEAT-029 (régularisation) ✅, FEAT-036 (récupérable/non) ✅, FEAT-041 (dépenses) ✅, FEAT-042 (mode charges) ✅ — toutes livrées.

## Problème

Aujourd'hui, la régularisation annuelle des charges est **100 % côté client et volatile** :
`ChargeRegularizationBalance` est calculé à la volée, le PDF « Avis de régularisation »
est rendu par le client (`charge_regularization_pdf_renderer.dart`) et partagé via
`WebShareService`. **Rien n'est persisté** — le contrôleur
(`charge_regularization_share_controller.dart`) le documente explicitement : « NI doc
Firestore à créer, NI marquage envoyé ».

Conséquence : un avis de régularisation transmis au locataire n'est **pas reproductible**.
Si une Dépense source (FEAT-041) ou un paiement de provision est modifié/supprimé après
l'envoi, le décompte re-généré diffère de celui que le locataire a reçu. Or l'avis est une
**pièce à valeur probante** (art. 23 loi du 6 juillet 1989, décret n°87-713) : il doit rester
figé et opposable.

## Objectif

Figer, au moment de la validation, un **instantané immuable** de la régularisation calculée —
solde, période, provisions encaissées, dépenses réelles et leur détail, identités — de sorte
que l'avis transmis au locataire soit reproductible à l'identique et conservé au titre de la
rétention légale (5 ans), exactement comme une quittance (`receipts`).

## Décisions produit (tranchées avec l'utilisateur, 2026-09-14)

1. **Contenu du snapshot** : détail figé — on stocke non seulement les totaux mais la liste
   des dépenses récupérables qui composent le montant réel (`lineItems`). La preuve doit
   survivre à une modification/suppression d'une Dépense source.
2. **Cycle de vie** : complet, miroir de `receipts` — créer + `markAsSent` (audit d'envoi) +
   `void`/réémettre en cas d'erreur.
3. **Collection** : `charge_statements/{id}` dédiée, CF-exclusive — pas une extension de
   `documents`. Modélise correctement l'objet légal, cohérent avec `receipts`.

## Architecture

Réplique fidèle du patron `receipts` (FEAT-007/019), qui est le précédent exact d'un objet
légal immuable dans ce projet :

- Nouvelle collection **`charge_statements/{id}`**, CF-exclusive, immuable.
- Trois callables (`functions/src/callable/charge_statements.ts`) :
  `finalizeChargeRegularization`, `voidChargeStatement`, `markChargeStatementAsSent`.
- Le **PDF reste rendu côté client** à partir des champs immuables stockés (aucun PDF ni
  Storage côté serveur — même décision que `receipts`, FEAT-019). Le doc Firestore est la
  preuve légale ; le PDF n'est qu'une présentation.
- La régularisation passe donc de « zéro serveur » à **CF-backed**. C'est inhérent : une
  persistance immuable et infalsifiable doit être CF-exclusive (les Rules interdisent toute
  écriture client, comme pour `receipts`).

### Garde-fous respectés (CLAUDE.md)

- **ADR 0003 / isolation prod-staging** : tous les callables écrivant Firestore utilisent
  `dbForRequest(request)`. Interdit `admin.firestore()` / `getFirestore()` ailleurs.
- **Rules obligatoires** deny-by-default, `isOwner`/`isFullyAuthed`, cross-user testées.
- **RGPD** : la nouvelle collection est ajoutée à `exportAccountData` (FEAT-047, #180).
- **Rétention légale** : pas de soft-delete, `create/update/delete: if false`.

## Modèle de données — `charge_statements/{id}`

Tous les champs sont **figés au finalize** (dénormalisation complète pour un PDF reproductible).

| Champ | Type | Rôle |
|---|---|---|
| `landlordId` | string | Propriétaire (ownership Rules). |
| `leaseId` | string | Bail régularisé. |
| `propertyId` | string | Bien rattaché. |
| `landlordFullName` | string | Denorm identité bailleur (loi 1989). |
| `landlordAddress` | string | Denorm adresse bailleur. |
| `tenantFullName` | string | Denorm identité locataire. |
| `tenantFirstName` | string | Denorm prénom locataire (corps du message de partage). |
| `propertyName` | string | Denorm nom du bien. |
| `propertyAddress` | string | Denorm adresse du logement. |
| `periodStart` | Timestamp | Début période de référence (inclus). |
| `periodEnd` | Timestamp | Fin période de référence (inclus). |
| `provisionsCollectedCents` | int | **Recalculé serveur** depuis `payments` sur la période (autoritatif). |
| `actualExpensesCents` | int | Total des dépenses réelles justifiées (décompte syndic). |
| `actualExpensesSource` | string | `'expenses'` (agrégé depuis Dépenses récupérables) \| `'manual'` (saisi). |
| `balanceCents` | int | Solde signé figé = `actualExpensesCents − provisionsCollectedCents`. |
| `lineItems` | array | Détail figé des dépenses récupérables composant le réel. Vide si `manual`. |
| `createdAt` | Timestamp | `serverTimestamp()` à la création. |
| `isVoided` | bool | Annulation non destructive (défaut `false`). |
| `voidedAt` | Timestamp\|null | Horodatage d'annulation. |
| `voidedReason` | string\|null | Motif d'annulation. |
| `sentAt` | Timestamp\|null | Audit d'envoi (Web Share). |
| `sentToEmail` | string\|null | Email destinataire (optionnel). |
| `schemaVersion` | int | `1`. |

### `lineItems[]` (forme figée)

Chaque élément : `{ expenseId: string, label: string, nature: string, amountCents: int, expenseDate: Timestamp }`.

Copie figée au moment du finalize — **ne référence pas** la Dépense vivante. Si une Dépense
source est ensuite éditée ou supprimée, `lineItems` reste inchangé (c'est le but : preuve
opposable). `expenseId` est conservé à titre de traçabilité, pas de jointure à la lecture.

### Direction du solde

`direction` (`dueByTenant` / `dueToTenant` / `balanced`) n'est **pas stockée** : elle est
dérivée de façon pure de `balanceCents` par
`ChargeRegularizationBalanceDirection` (déjà existant). Un seul champ signé source de vérité,
zéro risque d'incohérence.

## Callables — `functions/src/callable/charge_statements.ts`

Région `europe-west1`, `dbForRequest(request)`, helpers `requireAuthUid` / `requireString` /
`asBag` / `optionalTimestamp` (utils existants).

### `finalizeChargeRegularization`

- **Params** : `leaseId`, `periodStart`, `periodEnd`, `actualExpensesCents`,
  `actualExpensesSource` (`'expenses'|'manual'`), `lineItems[]` (peut être vide si `manual`).
- **Validations** :
  - auth (`requireAuthUid`) ;
  - fetch lease + ownership (`lease.landlordId == uid`) + lease non supprimé ;
  - **re-check serveur du gate légal** : le mode de charges effectif du bail doit être
    `provisions` (équivalent serveur de `Lease.canRegularizeCharges`, FEAT-042). Un bail au
    forfait est rejeté (`failed-precondition`) — on ne fige pas un décompte juridiquement
    inapplicable ;
  - `periodEnd > periodStart` ;
  - `actualExpensesCents >= 0` ;
  - `actualExpensesSource ∈ {expenses, manual}` ;
  - si `actualExpensesSource == 'expenses'` : chaque `lineItem` validé (montants ≥ 0), et la
    somme des `lineItems.amountCents` doit égaler `actualExpensesCents` (cohérence détail↔total,
    sinon `invalid-argument`).
- **Calcul serveur autoritatif** : `provisionsCollectedCents` est **recalculé** depuis les
  `payments` du bail dont la période recouvre `[periodStart, periodEnd]` (même logique que
  `ChargeProvisionsCalculator` côté client, mais côté serveur = infalsifiable). On ne fait pas
  confiance à une valeur de provisions envoyée par le client.
- **Dénormalisation** : fetch landlord (fullName + address requis, loi 1989) + champs bail
  (tenant/property déjà dénormalisés sur `leases`).
- **Mutation** : CREATE `charge_statements/{id}` avec tous les champs ci-dessus + flags à leur
  défaut + `createdAt = serverTimestamp()`.
- **Retour** : `{ statementId, balanceCents, direction }`.

### `voidChargeStatement`

- **Params** : `statementId`, `reason` (string, requis).
- fetch + ownership ; transaction : `isVoided=true`, `voidedAt=now()`, `voidedReason=reason`.
- **Idempotent** (noop si déjà voided). Retour `{ voided: true }`.

### `markChargeStatementAsSent`

- **Params** : `statementId`, `email?` (optionnel).
- fetch + ownership ; transaction : `sentAt=now()`, `sentToEmail=email ?? null`.
- Audit de la tentative d'envoi Web Share (pas de mail serveur). Idempotent (overwrite autorisé).
  Retour `{ sent: true }`.

## Firestore Rules

```
// charge_statements/{id} — IMMUABLES (loi 6 juillet 1989) → CF exclusive.
// Pas de soft-delete (rétention 5 ans). Voided reste lisible pour audit.
match /charge_statements/{id} {
  allow get:  if isOwner(resource.data.landlordId);
  allow list: if isOwner(resource.data.landlordId);
  // finalize / void / markAsSent en Callable.
  allow create, update, delete: if false;
}
```

Même forme et mêmes garanties que le bloc `receipts` (owner-scoped en get et list — les
décomptes d'un compte supprimé restent conservés 5 ans et ne doivent résoudre pour personne).

## Index Firestore

Composite pour l'historique par bail (tri antéchronologique) :

```
charge_statements: landlordId ASC, leaseId ASC, createdAt DESC
```

(Un second index `landlordId ASC, createdAt DESC` n'est ajouté que si une vue « tous les
décomptes du compte » apparaît — hors V1.)

## Client (Flutter)

### Données

- `lib/features/charge_regularization/data/charge_statement_repository.dart` (nouveau) :
  - lecture des décomptes d'un bail via `firestoreProvider` (jamais `FirebaseFirestore.instance`) ;
  - wrappers des 3 callables (`finalizeChargeRegularization`, `voidChargeStatement`,
    `markChargeStatementAsSent`).
- `lib/features/charge_regularization/domain/charge_statement.dart` (nouveau) : modèle figé
  + `lineItems`, avec `direction` dérivé (réutilise l'enum existant).

### Flux de finalisation

Le flux actuel `generateAndShare` (volatile) devient **« finaliser puis partager »** :

1. l'utilisateur ouvre la régul (dialog existant), calcule le solde comme aujourd'hui ;
2. nouvelle action **« Finaliser & figer le décompte »** → appelle
   `finalizeChargeRegularization` ;
3. le PDF est rendu **à partir des champs figés** retournés/relus (renderer existant
   `renderChargeRegularizationPdf`, `ChargeRegularizationPdfData` prend déjà ces champs) ;
4. partage via `WebShareService` (inchangé) ;
5. sur partage réussi → `markChargeStatementAsSent` (audit, miroir `receipts`).

### Historique sur la fiche bail

Nouvelle section/widget (fiche bail, à côté de `ChargeRegularizationSection`) listant les
décomptes figés du bail : période, solde + sens (`labelFr`), badges `envoyé` / `annulé`.
Actions par ligne : re-générer le PDF depuis le doc figé + re-partager ; annuler (`void`) avec
motif. Réémettre = annuler l'ancien puis relancer un nouveau finalize.

### Gates conservés

Le gate légal (`lease.canRegularizeCharges`, mode provisions) et le gate PRO (FEAT-044) restent
appliqués côté client comme aujourd'hui pour l'action de finalisation ; le re-check serveur du
gate légal dans `finalizeChargeRegularization` en est la frontière de sécurité.

## i18n

Nouvelles clés `.arb` FR + EN (finalize/void/sent, libellés historique, motif d'annulation,
badges). Respecter la parité imposée par `test/l10n/arb_parity_test.dart` (@description sur le
template EN). `flutter gen-l10n` (fichiers générés gitignorés).

## Tests

- **Functions (vitest, harness FakeFirestore/FakeAuthAdmin/makeRequest)** :
  - `finalizeChargeRegularization` : ownership refusé cross-user ; gate forfait rejeté ;
    `provisionsCollectedCents` recalculé serveur (ignore toute valeur client) ; cohérence
    `lineItems`↔total pour `source=expenses` ; création du doc avec flags par défaut.
  - `voidChargeStatement` : ownership ; idempotent ; non destructif.
  - `markChargeStatementAsSent` : ownership ; overwrite autorisé.
- **Rules tests** (`functions/rules-tests/`, émulateur) : cross-user get/list refusé ; client
  `create/update/delete` refusé ; voided lisible par l'owner.
- **Dart** : repository (lecture + wrappers) ; contrôleur finalize→share→markAsSent (états) ;
  PDF rendu depuis un snapshot figé ; `arb_parity_test` vert.

## Documentation d'état (Definition of Done)

Mettre à jour, pour les domaines touchés uniquement (`state-keeper` ciblé) :
`docs/state/schema/leases.md` (ou nouveau shard charge_statements), `functions/leases.md` (3
callables), `routes`/section fiche bail si pertinent, `FEATURES.md` (FEAT-033 → ✅ done),
`CHANGELOG.md`. Rappeler que **Rules + indexes se déploient via la CI** (develop → staging) ;
les **Cloud Functions restent en déploiement manuel délibéré**.

## Hors scope (V2)

- Flag `isStale` quand une Dépense source change après le finalize — le snapshot est figé
  **volontairement** ; pas de recomputation.
- Rapprochement automatique entre le décompte et le paiement qui le solde.
- Rappel/alerte annuelle « régularisation à faire » sur le dashboard.
- Vue transverse « tous les décomptes du compte » (au-delà de l'historique par bail).
- Ventilation multi-natures d'un décompte syndic en une saisie ; OCR du décompte.

## Légal / conformité

- Art. 23 loi du 6 juillet 1989 + décret n°87-713 : régularisation annuelle sur charges
  récupérables réelles, justifiée. Le snapshot fige la justification (période, provisions,
  réel, détail) et la rend opposable.
- Ne mélange que le récupérable (`provisionsCollectedCents` dérivé des provisions récupérables
  du bail ; `lineItems` = dépenses récupérables). Ni `leases.nonRecoverableChargesCents` ni
  `properties.condoFeesNonRecoverableCents` n'entrent dans le solde (risque de sur-facturation
  illégale).
- Rétention 5 ans, immuable — aligné sur `receipts` et `docs/LEGAL.md`.
- Format montants `1 234,56 €`, dates `DD/MM/YYYY`, cohérent avec les quittances.
