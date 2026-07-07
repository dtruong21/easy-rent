# Plan — [FEAT-041] Suivi des dépenses — entité first-class « l'argent qui sort »

> Plan d'architecture FINAL, issu du départage de 3 designs. **Socle retenu : Design 1 — SOURCE-OF-TRUTH**, greffé de 5 améliorations validées (voir « Provenance des décisions » en fin de doc).
> Story produit : [`docs/backlog/041-depenses.md`](../backlog/041-depenses.md). Cadrage : CRUD Dépense + historique + alimentation régularisation FEAT-029, rentabilité réelle FEAT-017 anticipée V1.1.
> ⚠️ `docs/state/SCHEMA.md` est PÉRIMÉ (parle de Supabase/Postgres/RLS) — la vérité est `firestore.rules` + `firestore.indexes.json` + `functions/src/callable/*.ts`. `state-keeper` à relancer en fin de chantier.

## Summary

FEAT-041 introduit une **collection Firestore canonique `expenses`** (camelCase, ponté snake_case comme `Property`/`Payment`/`Document`) qui devient la source unique de vérité de « l'argent qui sort ». La régularisation FEAT-029 et, en V1.1, la rentabilité FEAT-017 **dérivent** de cette collection au lieu de silos déconnectés. `expenses` est **CF-EXCLUSIVE** (comme `leases`/`payments`/`documents`) parce que sa création exige une validation cross-entity (le bien obligatoire et le bail optionnel appartiennent au même bailleur, avec `lease.propertyId == propertyId`) et une **dérivation serveur de la catégorie récupérable/non-récupérable** — garde-fou non contournable du décret 87-713. Le champ « Dépenses réelles » de la régularisation devient **pré-rempli** (somme des dépenses récupérables de la période) mais **reste ajustable** : `ChargeRegularizationBalance` est inchangé, seule la source de `actualExpensesCents` change. Les 3 champs statiques du bien (`propertyTaxAnnualCents`, `insurancePnoAnnualCents`, `condoFeesNonRecoverableCents`) **coexistent en fallback, zéro migration** en V1. Le moteur `profitability.dart` n'est **pas** touché : le hook réel-vs-estimé V1.1 vivra dans un **provider de présentation** (greffe Design 2). Effort **L (5-7 j)**, découpé en 3 sous-tickets < 3 j : **041a** CRUD, **041b** justificatif, **041c** régularisation.

---

## a) Modèle de données recommandé

### Collection `expenses/{id}` — CF-EXCLUSIVE

Nouvelle collection multi-doc, camelCase en Firestore, ponté snake_case via `firestoreDocToSnakeJson` (pattern `Property`/`Payment`/`Document`). Montants toujours en **centimes (int)**.

| Champ | Type | Notes | Immuable |
|---|---|---|---|
| `id` | string | = docId (UUID) | ✅ |
| `landlordId` | string | == `auth.uid`, FK → `landlords.id` | ✅ |
| `propertyId` | string | **OBLIGATOIRE**, FK → `properties.id` | ✅ |
| `propertyName` | string | Dénorm snapshot à la création (pattern `payments`) | — (re-snap sur update) |
| `leaseId` | string? | **OPTIONNEL**, FK → `leases.id` (ventilation régularisation par bail) | ✅ |
| `tenantLastName` | string? | Dénorm snapshot si `leaseId` fourni (affichage historique sans join) | — |
| `amountCents` | int | TTC, `>= 1` | — |
| `expenseDate` | timestamp | Date de la facture/décompte (≠ date de saisie) | — |
| `nature` | string | Enum fermé (voir table ci-dessous) | — |
| `category` | string | `'recoverable'` \| `'non_recoverable'` — **dérivée serveur** de `nature` | — |
| `categoryOverridden` | bool | `true` si le bailleur a forcé la catégorie par défaut (traçabilité juridique décret 87-713) | — |
| `periodYear` | int | **Exercice de rattachement** (ex. `2025`) — dérivé de `periodStart`, corrigeable ; index léger + filtre historique | — |
| `periodStart` | timestamp | Début période de rattachement. **Obligatoire si `category == recoverable`** | — |
| `periodEnd` | timestamp | Fin période de rattachement (`> periodStart`). **Obligatoire si `category == recoverable`** | — |
| `documentId` | string? | Justificatif — FK → `documents.id` (référence sortante) | — |
| `notes` | string? | Libellé libre, `<= 2000` | — |
| `createdAt` | timestamp | Serveur | ✅ |
| `updatedAt` | timestamp | Trigger `setUpdatedAtExpenses` | — |
| `deletedAt` | timestamp? | Soft-delete via `softDeleteEntity` | — |

**Note de conception « default to simple »** : `periodStart`/`periodEnd` obligatoires **uniquement** pour les dépenses récupérables (ce sont les seules agrégées en régularisation). Une dépense non-récupérable (taxe foncière) porte `periodYear` seul pour l'historique et la future rentabilité — pas besoin d'imposer une saisie de bornes fines qui ne sert à rien. `periodYear` est toujours présent (dérivé de `expenseDate` par défaut).

### Enum `nature` (liste fermée, alignée décret 87-713) + table de dérivation

Greffe Design 3 : la **table `NATURE_DEFAULT_CATEGORY` est la source unique de vérité juridique côté Cloud Function**, répliquée en enum Dart `ExpenseNature` pour la présélection UI. La dérivation serveur est non contournable ; le client ne fait que **présélectionner** (cohérence), il ne décide jamais.

Greffe Design 2 : **défauts conservateurs + verrouillage** — seule `condo_charges` est récupérable par défaut ; les natures fiscalement/juridiquement non-récupérables sont **verrouillées** (override interdit).

| `nature` | Catégorie par défaut | Override autorisé ? | Justification |
|---|---|---|---|
| `condo_charges` | `recoverable` | ✅ (→ non_recoverable) | Charges de copropriété : la part récupérable est la règle, mais certaines lignes du décompte sont non-récup. |
| `property_tax` | `non_recoverable` | ❌ **VERROUILLÉ** | Taxe foncière = jamais récupérable (hors TEOM, qui relève d'une ligne `condo_charges`). |
| `insurance_pno` | `non_recoverable` | ❌ **VERROUILLÉ** | Assurance PNO du bailleur = jamais récupérable. |
| `management_fees` | `non_recoverable` | ❌ **VERROUILLÉ** | Honoraires de gestion locative = jamais récupérables. |
| `works` | `non_recoverable` | ✅ (avec avertissement) | Travaux mixtes (art. 606 non-récup ; petit entretien récup). |
| `repair_maintenance` | `non_recoverable` | ✅ (avec avertissement) | Réparation/entretien : mixte selon le décret. |
| `other` | `non_recoverable` | ✅ (avec avertissement) | Fourre-tout conservateur. |

**Règle serveur (createExpense/updateExpense)** :
1. `category` = `NATURE_DEFAULT_CATEGORY[nature]` si le client ne force pas.
2. Si le client fournit une `category` ≠ défaut :
   - nature **verrouillée** → `HttpsError('failed-precondition', 'category_locked_for_nature')`.
   - nature ajustable → accepté, `categoryOverridden = true` persisté (auditable).
3. `insurance_gli` (assurance loyers impayés) n'est **pas** dans la liste V1 — regroupée sous `other` (décision à confirmer, cf. § Décisions).

### Enum Dart `ExpenseNature`

Nouveau `lib/features/expenses/domain/expense_nature.dart` : `sqlValue` / `label` FR / `icon` / `defaultCategory` (ExpenseCategory) / `isCategoryLocked` (bool) / `fromSql`. Réplique fidèle de la table CF — **mais la dérivation reste serveur** ; l'enum Dart ne sert qu'à présélectionner et à afficher l'avertissement d'override.

### Modèles Dart nouveaux

- `expense.dart` (freezed + `.g` + `.freezed`) — miroir de la collection, `@JsonKey(name: ...)` snake_case.
- `expense_nature.dart` — enum décrit ci-dessus.
- `expense_category.dart` — enum `recoverable` / `nonRecoverable` (`sqlValue` / `label` / chip color).
- `expense_filter.dart` — filtre historique (période / catégorie / nature).
- `expense_form_state.dart` — état de saisie (freezed).

---

## b) Propriété CRUD — CF-EXCLUSIVE

`expenses` est **CF-EXCLUSIVE**, PAS client-writable, exactement comme `leases`/`payments`/`documents`. Justification en 3 points qu'aucune Firestore rule ne peut couvrir proprement :

1. **Validation cross-entity** : `createExpense` doit vérifier que `propertyId` appartient à `uid` (obligatoire) ET que `leaseId` (si fourni) appartient à `uid` avec cohérence `lease.propertyId == propertyId`. Jusqu'à 2 `get()` cross-collection — impossible en rules, c'est exactement ce qui a rendu `leases`/`payments` CF-only (`lease_payment.ts`).
2. **Invariante juridique décret 87-713** : `category` **doit** être dérivée/validée serveur depuis `nature` (table `NATURE_DEFAULT_CATEGORY`), avec override refusé sur les natures verrouillées. Un client ne doit jamais pouvoir forger `category = recoverable` sur une taxe foncière → sur-facturation illégale au locataire.
3. **Dénormalisation + soft-delete protégé** : `propertyName`/`tenantLastName` snapshotés côté serveur (pattern `payments`) ; `deletedAt` jamais écrit directement côté client (`softDeleteEntity` étendu).

**Callables** (`functions/src/callable/expenses.ts`, nouveau) :

- **`createExpense`** — input : `{ propertyId, leaseId?, amountCents, expenseDate, nature, category?, periodStart?, periodEnd?, periodYear?, documentId?, notes? }`. Valide ownership property (obligatoire) + lease (optionnel, cohérence propertyId) + document (optionnel, ownership) ; dérive/valide `category` + `categoryOverridden` ; impose `periodStart`/`periodEnd` si `recoverable` ; dérive `periodYear` de `periodStart` (ou `expenseDate`) si absent ; snapshot `propertyName`/`tenantLastName`. Output : `{ expenseId, category, categoryOverridden }`.
- **`updateExpense`** — input : `{ id, ...champs mutables }`. `propertyId`/`leaseId`/`landlordId`/`createdAt`/`deletedAt` **immuables**. Re-dérive `category` si `nature` change (re-applique le verrouillage). Re-snapshot `propertyName` si le nom du bien a changé.
- **Soft-delete** : `softDeleteEntity` étendu — ajouter `'expenses'` au `SOFT_DELETABLE` (`soft_delete.ts` L32-38). Aucune garde métier propre (contrairement à `properties`/`documents`). **Attention** : le justificatif lié (`documentId`) sous `legalHold` reste protégé de son côté (voir § Justificatif) — soft-delete d'une dépense n'efface **pas** son document.
- **Trigger** : `setUpdatedAtExpenses` = `makeSetUpdatedAt('expenses')` (pattern des 7 triggers existants).
- **Exports** `index.ts` : `createExpense`, `updateExpense`, `setUpdatedAtExpenses`.

**Rollup `expense_rollups` : NON implémenté en V1.** Gardé en réserve documentée (greffe Design 3) : un agrégat dénormalisé maintenu par trigger `onExpenseWritten` est un **pattern nouveau** (aucun agrégat par trigger n'existe aujourd'hui) qui optimise une lecture non-goulot pour une app mono-bailleur. En V1, un scan client-side des dépenses d'un bien via l'index composite suffit largement. À reconsidérer en V1.1 **seulement si** un profil de lecture réel le justifie (rentabilité multi-période sur dashboard). Le modèle `expenses` (`expenseDate` + `category` + `periodYear`) alimente ce rollup plus tard **sans dette de modèle**.

---

## c) Intégration régularisation (FEAT-029)

**Stratégie : pré-remplir + conserver l'override manuel** (exigence PO « transition douce », décision produit #3). Le champ `Dépenses réelles (€)` (`charge_regularization_form.dart` L91-109) **reste éditable** mais est désormais pré-rempli par la somme des dépenses récupérables du bail/bien sur la période.

**Nouveau fichier** `lib/features/charge_regularization/application/recoverable_expenses_calculator.dart` — fonction pure **jumelle** de `sumChargeProvisionsForPeriod` :

```
int sumRecoverableExpensesForPeriod({
  required Iterable<Expense> expenses,
  required DateTime referenceStart,
  required DateTime referenceEnd,
})
```
Même logique de recouvrement d'intervalle et **même piège de fuseau** (`_dateOnly` → `.toLocal()` avant troncature à `DateTime(y,m,d)`, cf. `charge_provisions_calculator.dart` L64-67). **Garde-fou 87-713** : ne somme QUE `category == recoverable` (jamais `non_recoverable`), cohérent avec l'avertissement `charge_regularization_balance.dart` L42-45.

**Nouveau provider** `recoverableExpensesProvider((propertyId, leaseId?))` — stream des dépenses récupérables du bien (scan via index), filtrées optionnellement par bail.

**Fichiers modifiés** :
- `charge_regularization_dialog.dart` : ajouter `propertyId` au constructeur ; watch `recoverableExpensesProvider` ; pré-remplir `_actualExpensesController` + `_actualExpensesCents` au chargement ; flag `_userEditedExpenses` pour **ne pas écraser** une saisie manuelle après édition.
- `charge_regularization_form.dart` : libellé « Pré-rempli depuis N dépenses — modifiable » + section dépliable « Voir le détail (N dépenses) » avec accès aux justificatifs.

**Inchangés** : `ChargeRegularizationBalance` (domain), `sumChargeProvisionsForPeriod` (provisions encaissées sur `payments.chargesAmountCents`). **Non-régression** : 0 dépense → pré-remplissage = 0 → comportement V1 actuel strictement préservé.

**Cohérence période** : la régularisation peut porter sur une période glissante ; on **scanne les dépenses exactes** (fonction pure = référence de justesse) plutôt qu'un agrégat annuel — cohérent avec la non-implémentation du rollup en V1.

---

## d) Hook rentabilité FEAT-017 — V1.1 (anticipé, PAS codé en V1)

**Décision architecturale (greffe Design 2, corrige le Design 1)** : le hook réel-vs-estimé vit dans un **provider de présentation**, PAS dans un paramètre optionnel de `computeSnapshotForProperty`.

- Le moteur pur `lib/core/finance/profitability_snapshot.dart` et `profitability.dart` restent **strictement intacts**. Vérifié : `computeYieldNetPercent` / `computeMonthlyCashflowBeforeTaxCents` prennent déjà des `int?` (`profitability_snapshot.dart` L94-108). Élargir la signature du core = risque inutile de régression sur le simulateur FEAT-018.
- V1.1 : nouveau `realizedNonRecoverableProvider(propertyId, period)` (couche présentation) = somme des dépenses `category == non_recoverable` sur 12 mois glissants. Injecté **uniquement** dans `property_profitability_card.dart` avec la règle de bascule :
  `chargesForYield = realized > 0 ? realized : (champs statiques du bien)`.
- **Simulateur FEAT-018 totalement isolé** : il vit sur `investment_scenarios` (scénarios avant achat), ne lit ni `Property` ni `expenses` — aucune modif FEAT-041 ne le touche, par construction.

**Aucune dette de modèle** : `expenseDate` + `category` + `periodYear` suffisent à alimenter cet agrégat V1.1.

---

## e) Devenir des 3 champs statiques du bien

**COEXISTENCE EN FALLBACK — aucune migration en V1** (décision PO #4 confirmée, story L177).

- `property.propertyTaxAnnualCents`, `insurancePnoAnnualCents`, `condoFeesNonRecoverableCents` (`property.dart` L59-62) restent sur `properties`, **inchangés**.
- **V1** : ils alimentent la rentabilité FEAT-017 exactement comme aujourd'hui — FEAT-041 V1 ne touche pas `profitability.dart`.
- **V1.1** : bascule au réel quand `realized > 0` sur la période, sinon fallback estimation (§ d). Un bien fraîchement acquis sans historique garde son estimation → **évite un rendement net qui tomberait brutalement à zéro**.
- Après V1.1 : ils deviennent une « estimation prévisionnelle » (relabel UI possible), et restent la source du simulateur avant achat. **Jamais une suppression de champ** ; sur Firestore on cesse simplement de les écrire côté nouveaux flux si décision ultérieure.
- **Migration auto estimation → Dépenses REJETÉE** : une estimation annuelle n'a ni date de facture ni justificatif ; la migrer créerait des dépenses fantômes et un risque de double comptage.

---

## f) `firestore.rules` + `firestore.indexes.json`

### Rules — bloc `expenses/{id}` (copie du pattern `payments`/`documents`)

```
match /expenses/{id} {
  allow get: if isOwner(resource.data.landlordId) && isActive(resource);
  allow list: if isSignedIn();            // filtré côté requête .where landlordId==uid && deletedAt==null
  allow create, update, delete: if false; // CF-exclusive (createExpense/updateExpense + softDeleteEntity)
}
```
Anonyme exclu de facto (réservé aux flux CF `isFullyAuthed`, comme `properties`/`leases`). **Un anonyme n'accède jamais au registre de dépenses.**

### Rules — `documents` : contrainte `leaseId` assouplie (voir § Justificatif)

Aucun changement de rule pour `documents` (déjà `create/update/delete: if false`) — la modification porte sur le **callable** `createDocument`, pas sur les rules.

### Indexes composites (`firestore.indexes.json`) — toujours `landlordId` + `deletedAt` en tête

1. `landlordId ASC, propertyId ASC, deletedAt ASC, expenseDate DESC` — historique d'un bien.
2. `landlordId ASC, propertyId ASC, deletedAt ASC, category ASC, periodStart DESC` — filtre catégorie + agrégation régularisation par bien.
3. `landlordId ASC, leaseId ASC, deletedAt ASC, category ASC, periodStart DESC` — régularisation ventilée par bail.
4. `landlordId ASC, deletedAt ASC, expenseDate DESC` — vue globale + quota.
5. `landlordId ASC, propertyId ASC, deletedAt ASC, periodYear ASC, expenseDate DESC` — filtre historique par exercice (greffe Design 3, `periodYear`).

**Miroirs `deletedAt`-first** : anticiper les variantes générées par Firestore quand l'ordre des clauses `where` diffère (cohérent avec les doublons `payments`/`leases` existants relevés dans le state). À laisser `state-keeper` régénérer, mais prévu dès maintenant pour éviter un `FAILED_PRECONDITION` en QA. **Zéro `WHERE field == null` sans index** (convention projet).

---

## g) Justificatif — réutilisation de `documents` (FEAT-009)

Réutilise la collection `documents` existante (CF-EXCLUSIVE, Storage `documents/{uid}/{docId}`). **Point dur RÉEL** (`documents.ts` L63) : `leaseId` est aujourd'hui **obligatoire** (`requireString`) et validé par ownership du bail (L88-95). Une dépense peut n'avoir **aucun bail** (le décompte syndic arrive souvent après un départ locataire).

**Décision : `createDocument` v2 — `leaseId` OU `propertyId` (au moins un)** :
- `leaseId` → `requireString` devient optionnel ; ajout d'un `propertyId?` optionnel.
- Règle : au moins un des deux fourni, appartenant à `uid`. Si les deux fournis → valider `lease.propertyId == propertyId`.
- **Rétrocompat stricte** : un appel avec `leaseId` seul = comportement inchangé (tous les uploads de bail existants passent toujours). Tests dédiés sur les 4 chemins : `leaseId` seul / `propertyId` seul / les deux / aucun (→ erreur).
- Persistance : `leaseId` et `propertyId` tous deux nullable sur le doc.

**Nouvelle catégorie `expense_receipt`** :
- Ajout à `ALLOWED_CATEGORIES` (`documents.ts` L33-39).
- **Ajout à `LEGAL_HOLD_CATEGORIES`** (`documents.ts` L42) → `legalHold = true` **dès V1** (greffe : conservatisme légal). Rétention : facture/décompte = preuve locative 5 ans + comptable 10 ans (`docs/LEGAL.md` L37-38). `softDeleteEntity` refuse déjà le soft-delete d'un document `legalHold == true` (`soft_delete.ts` L85-90) → cohérent avec l'exigence PO L155 (« pas de suppression libre tant que la rétention n'est pas expirée »).

**Côté Dart** (regen freezed) :
- `Document.leaseId` : `String` → `String?`.
- Ajout `Document.propertyId` : `String?`.
- `DocumentCategory` (`document_category.dart`) : nouvelle valeur `expenseReceipt` (`sqlValue`/`label`/`icon`/`requiresLegalHold = true` + `fromSql`).

**Flux de saisie** (évite les orphelins) : upload Storage → `createDocument(category='expense_receipt', propertyId, leaseId?)` → `{ documentId }` → `createExpense(documentId)`. Si `createExpense` échoue après l'upload, le document reste (protégé par `legalHold`, pas de fuite RGPD) ; nettoyage cron identifié P2. Justificatif **recommandé, non bloquant** en V1 (§ Décisions).

---

## h) UI / Flutter

**Nouvelle feature** `lib/features/expenses/{data,domain,presentation,application}/`.

### Fiche bien (`property_detail_page.dart`)
- `ExpensesHistorySection(propertyId)` — carte résumé placée **entre la carte Rentabilité (`PropertyProfitabilityCard`) et la section Baux** : total 12 mois (récup / non-récup séparés) + CTA « Ajouter une dépense » + « Voir l'historique ».

### Routes (`go_router`, nesting sous `/properties/:id`, pattern `leases/:id/payments/new`)
- `/properties/:id/expenses` → `PropertyExpensesPage` — historique filtrable (période/exercice + catégorie/nature), totaux récup/non-récup séparés, accès justificatif (signed URL 5 min via `getDocumentDownloadUrl`). Ouvert en **`push()`** (conserve la stack, cohérent FEAT-030).
- `/properties/:id/expenses/new` → `ExpenseFormPage` (création ; `leaseId` pré-rempli si un bail actif est passé en `extra`).
- `/properties/:id/expenses/:eid/edit` → `ExpenseFormPage` (édition). **`pop()`** au succès (retour fiche, cohérent FEAT-030).

### Point d'entrée secondaire
- Fiche bail : bouton « Ajouter une dépense liée » (pré-remplit `propertyId` + `leaseId`), en **`push()`**.

### Widgets
- `expense_form.dart` : bien pré-sélectionné, bail optionnel (dropdown des baux du bien), `nature` picker (présélection `category`), champ catégorie avec **avertissement explicite si bascule d'une nature ajustable vers récupérable** (risque 87-713, pas de blocage dur) et **verrouillage dur** sur les natures verrouillées, `amountCents`, `expenseDate`, période de rattachement (dérivée de la date, corrigeable), upload justificatif, notes.
- `expense_list_tile.dart` : nature + montant + date + chip récupérable/non-récupérable + accès justificatif.
- `expense_filter_bar.dart` : filtre période/exercice + nature, totaux récup/non-récup affichés séparément.
- Dialog régularisation : détail dépliable « N dépenses » + libellé « Pré-rempli — modifiable » (§ c).

**Tout réservé `isFullyAuthed`** — un anonyme n'accède pas au registre de dépenses (comme `properties`/`tenants`).

---

## i) Stratégie de tests

### Cloud Functions (vitest, framework en place — cf. `finalize_anonymous_upgrade.test.ts`)
- `createExpense` : ownership property OK/KO ; lease optionnel cohérence `propertyId` OK/KO ; dérivation `category` par nature ; **override refusé sur nature verrouillée** (`property_tax`/`insurance_pno`/`management_fees`) ; override accepté + `categoryOverridden=true` sur nature ajustable ; `periodStart/End` obligatoires si récupérable ; dérivation `periodYear` ; snapshot `propertyName`/`tenantLastName` ; `documentId` ownership.
- `updateExpense` : immuables (`propertyId`/`leaseId`/`landlordId`/`createdAt`) ; re-dérivation `category` sur changement de `nature`.
- `softDeleteEntity('expenses')` : ownership ; idempotence ; le `documentId` `legalHold` **survit**.
- `createDocument` v2 : 4 chemins `leaseId`/`propertyId`/les-deux/aucun ; **rétrocompat** `leaseId` seul inchangée ; `expense_receipt` → `legalHold = true`.

### Tests Dart
- `sumRecoverableExpensesForPeriod` : recouvrement d'intervalle, piège fuseau (`_dateOnly`), exclusion stricte des `non_recoverable`, filtre `leaseId` optionnel, 0 dépense → 0.
- `ExpenseNature` : `defaultCategory` + `isCategoryLocked` par valeur, `fromSql` round-trip.
- Widget `charge_regularization_dialog` : pré-remplissage depuis dépenses ; `_userEditedExpenses` n'écrase pas une saisie manuelle ; 0 dépense → comportement V1 inchangé.
- Widget `expense_form` : verrouillage catégorie ; avertissement override ; validation montant/date/période.

### RLS (émulateur, cross-user)
- Un bailleur B ne peut **jamais** `get`/`list` les `expenses` de A.
- Écriture directe client sur `expenses` refusée (`create/update/delete: if false`).
- `deletedAt` non écrivable côté client.

### QA manuel
- AC Gherkin story L107-150 : dépense récupérable avec justificatif (catégorie présélectionnée) ; taxe foncière (non-récup verrouillée) ; historique filtré par exercice (totaux séparés) ; régularisation pré-remplie à 980,00 € + détail consultable + ajustable.

---

## j) Sécurité / RGPD (résumé RLS en un paragraphe)

`expenses` est CF-EXCLUSIVE : lecture `get/list` autorisée uniquement au propriétaire actif (`isOwner(landlordId) && isActive(resource)`, filtre `deletedAt==null` côté requête), toute écriture directe client refusée (`create/update/delete: if false`) — les mutations passent par les callables Admin SDK `createExpense`/`updateExpense` (qui valident ownership cross-entity property+lease, dérivent la catégorie côté serveur comme garde-fou décret 87-713, et snapshotent la dénormalisation) et le soft-delete par `softDeleteEntity` étendu, `deletedAt` n'étant jamais écrivable par le client. Un anonyme n'a aucun accès (flux `isFullyAuthed` uniquement). **RGPD** : une dépense concerne le bien, pas nécessairement le locataire ; si `tenantLastName` (dénorm) ou une note mentionne le locataire, elle suit le même régime que les autres données bailleur (accès restreint au propriétaire, export/effacement du compte via le flux RGPD existant). **Rétention** : le justificatif `expense_receipt` porte `legalHold = true` (5 ans probante / 10 ans comptable, `docs/LEGAL.md`), donc indélébile tant que la rétention n'est pas expirée — la dépense elle-même reste soft-deletable, mais son justificatif est protégé.

---

## k) Fichiers touchés

### Créés
- `functions/src/callable/expenses.ts` — `createExpense`, `updateExpense`, `setUpdatedAtExpenses`, table `NATURE_DEFAULT_CATEGORY`.
- `lib/features/expenses/domain/expense.dart` (+ `.g` + `.freezed`).
- `lib/features/expenses/domain/expense_nature.dart`.
- `lib/features/expenses/domain/expense_category.dart`.
- `lib/features/expenses/domain/expense_filter.dart`.
- `lib/features/expenses/domain/expense_form_state.dart` (+ `.freezed`).
- `lib/features/expenses/data/expenses_repository.dart`.
- `lib/features/expenses/application/expenses_provider.dart`, `expense_form_controller.dart`.
- `lib/features/expenses/presentation/property_expenses_page.dart`, `expense_form_page.dart`, `widgets/expenses_history_section.dart`, `expense_list_tile.dart`, `expense_filter_bar.dart`.
- `lib/features/charge_regularization/application/recoverable_expenses_calculator.dart`.

### Modifiés
- `functions/src/callable/documents.ts` — `createDocument` v2 (`leaseId` optionnel + `propertyId?`), `expense_receipt` dans `ALLOWED_CATEGORIES` + `LEGAL_HOLD_CATEGORIES`.
- `functions/src/callable/soft_delete.ts` — `'expenses'` dans `SOFT_DELETABLE`.
- `functions/src/index.ts` — exports des nouvelles fonctions.
- `firestore.rules` — bloc `match /expenses/{id}`.
- `firestore.indexes.json` — 5 index composites (+ miroirs).
- `lib/features/documents/domain/document.dart` — `leaseId` → `String?`, ajout `propertyId String?`.
- `lib/features/documents/domain/document_category.dart` — `expenseReceipt`.
- `lib/features/charge_regularization/presentation/widgets/charge_regularization_dialog.dart` — `propertyId` + pré-remplissage.
- `lib/features/charge_regularization/presentation/widgets/charge_regularization_form.dart` — libellé + détail dépliable.
- `lib/features/properties/presentation/property_detail_page.dart` — `ExpensesHistorySection`.
- Router go_router — 3 routes sous `/properties/:id/expenses`.

### NON touchés (V1)
- `lib/core/finance/profitability.dart` + `profitability_snapshot.dart` (hook V1.1 en présentation).
- `lib/features/**/investment_scenarios/**` (simulateur FEAT-018 isolé).
- `lib/features/charge_regularization/domain/charge_regularization_balance.dart` + `charge_provisions_calculator.dart`.
- 3 champs statiques `property.dart` (coexistence fallback).

### Dette d'état à corriger après implémentation
- `docs/state/SCHEMA.md` PÉRIMÉ (Supabase) — à régénérer par `state-keeper`.
- Nouvelle collection `expenses` + rules + indexes + callables + `createDocument` v2 → à refléter dans `SCHEMA.md` / `FUNCTIONS.md` / `ROUTES.md` / `FEATURES.md`.

---

## Ordre d'exécution étape par étape

**FEAT-041a — CRUD Dépense (M, 2-3 j)**
1. `expenses.ts` : `createExpense`/`updateExpense`/`setUpdatedAtExpenses` + `NATURE_DEFAULT_CATEGORY` ; export `index.ts` (via `supabase-dev`/functions-dev).
2. `soft_delete.ts` : ajouter `'expenses'` au `SOFT_DELETABLE`.
3. `firestore.rules` (bloc `expenses`) + `firestore.indexes.json` (5 index) ; déployer indexes.
4. Modèles Dart (`expense.dart`, `expense_nature.dart`, `expense_category.dart`, filtres, form state) + `build_runner`.
5. Repository + providers + `ExpenseFormPage` + `PropertyExpensesPage` + `ExpensesHistorySection` + routes.
6. Tests functions (createExpense/updateExpense/softDelete) + tests Dart (nature/enum) + RLS cross-user.

**FEAT-041b — Justificatif via `documents` assoupli (S-M, 1-2 j)**
7. `documents.ts` : `createDocument` v2 (`leaseId` optionnel + `propertyId?` + `expense_receipt` + `legalHold`).
8. Dart : `Document.leaseId String?` + `propertyId String?` + `DocumentCategory.expenseReceipt` + `build_runner`.
9. Câblage upload justificatif dans `ExpenseFormPage` (upload → createDocument → createExpense).
10. Tests rétrocompat `createDocument` (4 chemins) + `legalHold` `expense_receipt`.

**FEAT-041c — Alimentation régularisation FEAT-029 (M, 1,5-2 j)**
11. `recoverable_expenses_calculator.dart` (fonction pure) + `recoverableExpensesProvider`.
12. `charge_regularization_dialog.dart` (pré-remplissage + `_userEditedExpenses`) + `charge_regularization_form.dart` (libellé + détail).
13. Tests calculator (recouvrement/fuseau/exclusion non-récup) + widget (pré-remplissage, override manuel, 0 dépense).

**Clôture**
14. `code-reviewer` + `security-auditor`.
15. `state-keeper` : régénérer `SCHEMA.md`/`FUNCTIONS.md`/`ROUTES.md`/`FEATURES.md`.
16. Déploiement staging (rappel : `--pwa-strategy=none`, hard refresh).

---

## Absorption de FEAT-033 (archivage régularisation)

FEAT-041 **absorbe partiellement FEAT-033**. L'objectif « retrouver l'historique en cas de litige » est atteint en amont : chaque **dépense** est persistée, catégorisée, justifiée (`legalHold`) et datée dès sa saisie — l'historique existe dépense par dépense, indépendamment de toute régularisation, avec justificatif indélébile 5-10 ans. **Ce qui reste hors V1** (reliquat FEAT-033) : l'**instantané figé** de la régularisation validée (solde + PDF envoyé + date de validation), car une dépense en amont pourrait être modifiée après l'envoi de l'avis au locataire. En V1, la traçabilité minimale est assurée par `createdAt`/`updatedAt` sur chaque dépense (jamais d'écrasement silencieux). L'instantané figé reste explicitement en **V1.1** (décision PO #6) — à trancher après usage réel. Aucune structure `receipts`-like n'est créée en V1.

---

## Provenance des décisions (départage 3 designs)

Socle : **Design 1 (SOURCE-OF-TRUTH)**. Greffes intégrées :
- **[Design 2]** Hook rentabilité V1.1 en **provider de présentation** (`realizedNonRecoverableProvider` dans `property_profitability_card.dart`), moteur `profitability.dart` strictement intact — évite d'élargir la signature du core et isole le simulateur FEAT-018.
- **[Design 2]** Défauts d'enum **conservateurs** + natures **verrouillées** (`property_tax`/`insurance_pno`/`management_fees` non ajustables), combinés au flag **`categoryOverridden` auditable** [Design 1].
- **[Design 3]** Champ **`periodYear`** dérivé (filtrage historique par exercice + index léger) + table **`NATURE_DEFAULT_CATEGORY`** côté CF comme source unique répliquée en enum Dart.
- **[Design 3]** Rollup `expense_rollups` **gardé en réserve documentée pour V1.1 uniquement** (non implémenté en V1) + anticipation des **miroirs d'index `deletedAt`-first**.

---

## ❓ Décisions à trancher avant implémentation (consolidées PO + technique)

| # | Question | Recommandation par défaut |
|---|---|---|
| 1 | **Rattachement bail** obligatoire ou optionnel ? (PO #1) | **Optionnel**, fortement suggéré si un bail est actif sur la période choisie. Le décompte syndic arrive souvent après un changement de locataire. |
| 2 | **Catégorie** dérivée stricte ou ajustable ? (PO #2) | **Présélection par nature + ajustable UNIQUEMENT sur natures ajustables** (`condo_charges`/`works`/`repair_maintenance`/`other`), avec avertissement. **Verrouillée** sur `property_tax`/`insurance_pno`/`management_fees`. Override tracé par `categoryOverridden`. |
| 3 | **Liste des natures** fermée ou extensible ? (PO #3) | **Fermée** en V1 (7 natures + `other`), pas de texte libre — sécurise le décret 87-713. |
| 4 | **3 champs statiques** : migration / coexistence / conservation ? (PO #4) | **Coexistence en fallback, zéro migration.** Bascule au réel en V1.1 quand `realized > 0`, sinon estimation. |
| 5 | **Rentabilité sur réel** en V1 ou V1.1 ? (PO #5) | **V1.1**, séparée. Le CRUD + alimentation régularisation (V1) est livrable/testable seul ; coupler augmente le risque > 3 j. |
| 6 | **Reliquat FEAT-033** (instantané figé) V1 ou différé ? (PO #6) | **V1.1.** Traçabilité minimale (`updatedAt`) suffit pour démarrer ; risque réel mais rare. |
| 7 | **OCR** du décompte syndic ? (PO #7) | **Saisie manuelle stricte en V1.** OCR multi-lignes = chantier lourd distinct (V2+). |
| 8 | **Justificatif recommandé ou obligatoire ?** (technique / PO L41) | **Recommandé, non bloquant en V1** pour ne pas frictionner la saisie. Passer à « obligatoire si dépense servant de preuve en régularisation » envisageable une fois l'usage confirmé. À surfacer : le PO souhaite « obligatoire si preuve ». |
| 9 | **`expense_receipt` sous `legalHold` dès V1 ?** (technique) | **Oui, `legalHold = true` dès V1** (conforme `docs/LEGAL.md` + PO L155). Conséquence : une dépense justifiée devient indélébile 5-10 ans (juridiquement correct mais rigide) — à assumer explicitement. |
| 10 | **`insurance_gli`** (assurance loyers impayés) : nature dédiée ou `other` ? (technique) | **`other` en V1** (non-récupérable). Ajouter une nature dédiée si besoin comptable émerge (V1.1). |
| 11 | **Rollup `expense_rollups`** dès V1 ? (technique) | **Non.** Scan client-side via index suffit pour mono-bailleur. Réserve V1.1 si profil de lecture réel. |
| 12 | **Périmètre de `updateExpense`** : quels champs mutables ? (technique) | `amount`/`date`/`nature`/`category`/`period*`/`documentId`/`notes` mutables ; `propertyId`/`leaseId`/`landlordId`/`createdAt`/`deletedAt` **immuables** (changer de bien = supprimer + recréer). |
