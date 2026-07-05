# Plan — [FEAT-006] Enregistrer un paiement de loyer

## 1. Vue d'ensemble

**Objectif** : permettre au bailleur de saisir les paiements mensuels d'un bail actif (CRUD complet + soft-delete). Débloquera FEAT-007 (quittance PDF) qui lira directement `payments.rent_amount_cents` / `charges_amount_cents` (loi 1989 art. 21).

**Dépendances** : FEAT-001 (auth), FEAT-002 (schéma + pattern RLS), FEAT-005 (bail = entité pivot, pré-remplissage montants).

**Scope** : table `payments` (public+dev) + trigger ownership + RPC soft-delete + module Flutter `lib/features/payments/` + section "Paiements" sur `/leases/:id` (remplace le placeholder actuel — voir [`lib/features/leases/presentation/lease_detail_page.dart:380-406`](../../lib/features/leases/presentation/lease_detail_page.dart)).

**Hors scope** : génération PDF (FEAT-007), email (FEAT-008), page `/payments` globale multi-bail (P1), gestion trop-perçus, hard-delete.

---

## 2. Modèle de données — `payments` (public + dev)

### 2.1 Colonnes

| Colonne | Type | Contraintes / commentaire |
|---|---|---|
| `id` | `uuid` | PK, DEFAULT `gen_random_uuid()` |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT — dénormalisé pour RLS directe sans jointure (pattern leases) |
| `period_start` | `date` | NOT NULL, CHECK BETWEEN `'1900-01-01'` AND `'2100-12-31'` (pattern lease date bounds) |
| `period_end` | `date` | NOT NULL, CHECK `period_end > period_start` AND BETWEEN `'1900-01-01'` AND `'2100-12-31'` |
| `paid_at` | `date` | NOT NULL, CHECK BETWEEN `'1900-01-01'` AND `'2100-12-31'` |
| `rent_amount_cents` | `integer` | NOT NULL CHECK `> 0` — loyer HC en centimes |
| `charges_amount_cents` | `integer` | NOT NULL DEFAULT 0 CHECK `>= 0` |
| `payment_method` | `text` | NOT NULL CHECK IN (`'virement'`, `'cheque'`, `'especes'`, `'prelevement'`, `'autre'`) |
| `notes` | `text` | NULL, CHECK `char_length(notes) <= 500` |
| `created_at` | `timestamptz` | NOT NULL DEFAULT `now()` |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT `now()` |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC uniquement |

**Note décisions produit** : pas de CHECK haut sur `rent_amount_cents`/`charges_amount_cents` (autorise trop-perçu) ; pas de UNIQUE sur `(lease_id, period_start, period_end)` (doublons autorisés).

### 2.2 Indexes

```
idx_public_payments_lease_id       (lease_id)
idx_public_payments_landlord_id    (landlord_id)
idx_public_payments_period_start_desc (lease_id, period_start DESC)  -- tri liste
idx_public_payments_active_partial (lease_id) WHERE deleted_at IS NULL  -- vue active
```
Équivalents `idx_dev_payments_*` sur `dev.payments`.

### 2.3 Triggers (pattern strictement aligné FEAT-002)

- **`tr_00_assert_payment_lease_ownership`** BEFORE INSERT OR UPDATE
  - Fonction `public.assert_payment_lease_ownership()` SECURITY DEFINER + `SET search_path = public`
  - Valide : (a) `lease_id` existe dans `public.leases` (sinon ERRCODE 23514), (b) `lease.landlord_id = NEW.landlord_id` (sinon ERRCODE 23514 "Ownership mismatch")
  - Bypass RLS intentionnel (cf. justification dans [`20260528120000_feat002_data_model.sql:380-386`](../../supabase/migrations/20260528120000_feat002_data_model.sql))
  - Miroir `dev.assert_payment_lease_ownership()` lit `dev.leases`
  - **Important** : ne vérifie pas le statut du bail (la règle UI "bail clôturé → bouton désactivé" est purement frontend ; on autorise au niveau DB un paiement rétroactif sur bail `terminated`/`archived` car cas légitimes — régularisation, dernière mensualité après clôture).

- **`tr_01_prevent_protected_columns_change_payments`** BEFORE INSERT OR UPDATE
  - Réutilise `public.prevent_protected_columns_change()` (déjà déployée FEAT-002, aucune duplication)
  - Bloque modification directe de `deleted_at`, `created_at` sauf flag `app.allow_deleted_at_change = '1'`

- **`tr_02_set_updated_at_payments`** BEFORE UPDATE
  - Réutilise `public.set_updated_at()`

### 2.4 Policies RLS

| Policy | Op | Condition |
|---|---|---|
| `payments_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `payments_insert_own` | INSERT | WITH CHECK `landlord_id = auth.uid()` |
| `payments_update_own` | UPDATE | USING `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK `landlord_id = auth.uid()` |

Aucune policy DELETE. Identique sur les schémas public et dev.

### 2.5 RPC `soft_delete_payment(p_id uuid)`

Réplique exacte de [`soft_delete_lease`](../../supabase/migrations/20260528120000_feat002_data_model.sql) (lignes 716–740) :
- `SECURITY DEFINER`, `SET search_path = public`
- `SET LOCAL app.allow_deleted_at_change = '1'`
- `UPDATE public.payments SET deleted_at = now() WHERE id = p_id AND landlord_id = auth.uid() AND deleted_at IS NULL`
- `RAISE EXCEPTION ERRCODE = 'P0002'` si NOT FOUND
- `REVOKE ALL FROM PUBLIC; GRANT EXECUTE TO authenticated`
- Miroir `dev.soft_delete_payment(p_id uuid)` opère sur `dev.payments`

### 2.6 Vérification fin de migration

Ajouter `SELECT dev.assert_rls_both_schemas('payments');` à la fin (pattern FEAT-002 ligne 846).

---

## 3. Migration à créer

**Nom exact** : `supabase/migrations/20260601HHMMSS_feat006_payments.sql` (timestamp à figer par `supabase-dev` au moment de l'exécution).

**Structure** (sections, dans l'ordre) :
1. `BEGIN;`
2. Section 1 — Fonctions `public.assert_payment_lease_ownership()` + `dev.assert_payment_lease_ownership()`
3. Section 2 — Table `public.payments` + index + RLS + policies + triggers tr_00, tr_01, tr_02
4. Section 3 — Table `dev.payments` (miroir) + index + RLS + policies + triggers
5. Section 4 — RPC `public.soft_delete_payment(uuid)` + `dev.soft_delete_payment(uuid)` (REVOKE/GRANT)
6. Section 5 — `SELECT dev.assert_rls_both_schemas('payments');`
7. `COMMIT;`

**Convention multi-env** : appliquer les changements aux DEUX schémas dans la même migration (cf. [`docs/ENVIRONMENTS.md:29-55`](../ENVIRONMENTS.md)). Le miroir DEV doit être un copier-coller exact du PROD avec préfixe `dev.`.

**Pas de migration séparée** pour "date bounds" — intégrer directement les CHECK 1900–2100 sur les 3 colonnes date dès la création (leçon FEAT-005, hardening rétroactif évité).

---

## 4. Structure Flutter — `lib/features/payments/`

Suit strictement le pattern FEAT-005 ([`lib/features/leases/`](../../lib/features/leases/)).

```
lib/features/payments/
├── domain/
│   ├── payment.dart                       # freezed + json_serializable, JsonKey snake_case, date helpers
│   ├── payment.freezed.dart               # GÉNÉRÉ
│   ├── payment.g.dart                     # GÉNÉRÉ
│   ├── payment_method.dart                # enum sealed : virement, cheque, especes, prelevement, autre + fromSql/sqlValue/label
│   ├── payment_form_state.dart            # freezed sealed : idle | submitting | success | error
│   └── payment_form_state.freezed.dart    # GÉNÉRÉ
├── data/
│   └── payment_repository.dart            # interface + SupabasePaymentRepository + provider Riverpod + exceptions
├── application/
│   ├── lease_payments_provider.dart       # AsyncNotifier family<List<Payment>, String leaseId> — liste paiements d'un bail
│   ├── payment_detail_provider.dart       # FutureProvider family<Payment, String paymentId>
│   └── payment_form_controller.dart       # StateNotifier<PaymentFormState> — submit (create/update) + delete
└── presentation/
    ├── payment_form_page.dart             # PaymentFormPage (create) + PaymentEditPage (update) — pattern lease_form_page.dart
    └── widgets/
        ├── payment_list_section.dart      # Card "Paiements" intégrée dans LeaseDetailPage (remplace _PaymentsPlaceholder)
        ├── payment_list_tile.dart         # Tile : période + montant + mode + actions (edit/archive)
        ├── payment_form.dart              # Form widget réutilisable create+edit
        └── payment_amount_warning.dart    # Banner non bloquante : "Montant inférieur au bail" / "Montant supérieur au bail"
```

**Décisions clés** :
- **Pas de `payments_list_page.dart` globale** dans cette feature. La liste vit dans la section paiements de la fiche bail. La page `/payments` multi-bail est explicitement P1+ (cf. story §"Vue liste paiements page dédiée optionnelle" — reportée).
- **Repository** méthodes : `listForLease(String leaseId)`, `getById(String id)`, `create({...})`, `update(Payment payment)`, `archive(String id)` (via RPC). Aucune méthode `close` (pas d'équivalent au statut bail).
- **Provider liste** : `AsyncNotifierProvider.family<LeasePaymentsNotifier, List<Payment>, String>` indexé par `leaseId` (un cache par bail, invalidation chirurgicale).
- **Form controller** : à invalider `leasePaymentsProvider(leaseId)` + `paymentDetailProvider(id)` après succès. Pattern exact `LeaseFormController` ([`lease_form_controller.dart:74`](../../lib/features/leases/application/lease_form_controller.dart)).

---

## 5. Routes go_router

**Décision : routes dédiées** (pas de modal) pour rester cohérent avec le pattern leases/tenants/properties — réutilisation de back-stack, deep-linking, tests widget par route, support PWA install.

À ajouter dans [`lib/core/router/app_router.dart`](../../lib/core/router/app_router.dart) après les routes leases (ligne 124) :

```
/leases/:id/payments/new            → PaymentFormPage(leaseId: ...)
/leases/:id/payments/:pid/edit      → PaymentEditPage(leaseId: ..., paymentId: ...)
```

**Justification du nesting sous `/leases/:id/`** :
- Le `leaseId` est requis pour pré-remplir `rent_amount_cents` / `charges_amount_cents` depuis le bail, et un paiement existe TOUJOURS dans le contexte d'un bail.
- Permet à la BackButton de renvoyer naturellement vers `/leases/:id` (UX cohérente).
- Évite une route orpheline `/payments/new` qui exigerait un selector "Choisir le bail".

**Pas de route `/leases/:id/payments/:pid` (detail)** : la liste de paiements affiche déjà toutes les colonnes ; un tap ouvre directement le mode édition.

Mise à jour `docs/state/ROUTES.md` requise post-merge (state-keeper).

---

## 6. Helpers — réutilisation vs création

| Helper | Action | Source |
|---|---|---|
| `MoneyFormat.eurosToCents` / `centsToEuros` / `formatEurosFromCents` / `centsToInput` | **Réutilise tel quel** | [`lib/core/utils/money_format.dart`](../../lib/core/utils/money_format.dart) |
| Mappeur erreurs Postgrest → message FR | **Réutilise** | [`lib/core/utils/postgrest_error_mapper.dart`](../../lib/core/utils/postgrest_error_mapper.dart) |
| Dialog soft-delete | **Réutilise** `ArchiveConfirmDialog` (titre + entityLabel adaptés) | [`lib/core/widgets/archive_confirm_dialog.dart`](../../lib/core/widgets/archive_confirm_dialog.dart) |
| **`payment_form_validators.dart`** (NOUVEAU) | À créer dans `lib/core/utils/` — pattern strictement aligné [`lease_form_validators.dart`](../../lib/core/utils/lease_form_validators.dart) | NEW |

**Contenu `payment_form_validators.dart`** :
- `validatePeriodStart(DateTime?)` — non null, bornes 1900–2100
- `validatePeriodEnd(DateTime?, DateTime? start)` — non null, > start, bornes
- `validatePaidAt(DateTime?)` — non null, bornes (autorisé dans le futur : prélèvement programmé)
- `validateRentAmount(String?)` — alias de `LeaseFormValidators.validateRentAmount` ? **À factoriser** : extraire dans un fichier partagé `money_validators.dart` (rent/charges identiques sur lease et payment) — ou plus simplement, dupliquer 4 lignes (préférer la duplication courte plutôt qu'une abstraction prématurée — code is cheap).
- `validateChargesAmount(String?)` — idem
- `validatePaymentMethod(PaymentMethod?)` — non null
- `validateNotes(String?)` — optionnel, max 500 caractères

**Question architecture** : factoriser `validateRentAmount` / `validateChargesAmount` dans `money_validators.dart` partagé entre leases et payments ? Recommandation : OUI, refactor mineur, supprime 30 lignes de duplication et fait évoluer les bornes au même endroit. À planifier dans un commit séparé en début de feature.

---

## 7. Plan de tests

### 7.1 Tests SQL RLS (`supabase/tests/rls_payments.sql`)

Pattern [`rls_leases.sql`](../../supabase/tests/rls_leases.sql) (31 tests). Couverture cible :

1. User A voit ses paiements (public + dev) — 2 tests
2. User A ne voit PAS les paiements de User B (public + dev) — 2 tests
3. User A ne peut PAS UPDATE un paiement de User B — 2 tests
4. INSERT avec `landlord_id = auth.uid()` réussit — 2 tests
5. INSERT avec `landlord_id` d'un autre user → erreur 42501 — 2 tests
6. **Trigger `assert_payment_lease_ownership`** : INSERT avec `lease_id` d'un autre user (mais `landlord_id = self`) → ERRCODE 23514 — 2 tests
7. Trigger : INSERT avec `lease_id` inexistant → ERRCODE 23514 — 2 tests
8. CHECK `period_end > period_start` refusé — 1 test
9. CHECK `rent_amount_cents > 0` refusé — 1 test
10. CHECK `charges_amount_cents >= 0` refusé (négatif) — 1 test
11. CHECK `payment_method` invalide refusé — 1 test
12. CHECK `notes` > 500 caractères refusé — 1 test
13. CHECK date bounds (1850, 2200) refusé — 2 tests
14. Soft-delete via RPC : ligne invisible mais existante — 2 tests
15. RPC `soft_delete_payment` cross-user → NOT FOUND — 2 tests
16. UPDATE direct de `deleted_at` refusé (ERRCODE 42501) — 2 tests
17. INSERT `deleted_at = now()` refusé — 2 tests
18. INSERT antidaté `created_at` corrigé silencieusement — 1 test
19. RLS activée sur les deux schémas — 1 test (assert_rls_both_schemas)

Total cible : ~30 tests.

### 7.2 Tests unitaires Dart (`test/unit/`)

- `payment_form_validators_test.dart` — chaque validator, cas nominal/limites/null
- `money_format_test.dart` — **étendre l'existant** si non couvert : arrondis (`84.99 € → 8499 cts`), saisie virgule/point, valeur négative → null, overflow int32 → null
- `payment_method_test.dart` — `fromSql`/`sqlValue`/`label` round-trip
- `payment_repository_test.dart` — mock Supabase, vérifie payload sans `landlord_id`/`id`/timestamps, vérifie appel RPC pour archive

### 7.3 Tests widget (`test/widget/`)

- `payment_form_test.dart` — pré-remplissage depuis bail, warning montant inférieur/supérieur, validation dates, submit OK, submit error
- `payment_list_section_test.dart` — tri `period_start DESC`, bouton "Ajouter" désactivé si bail clôturé (message "Ce bail est clôturé."), liste vide → état placeholder
- `payment_archive_dialog_test.dart` — confirmation + appel RPC

### 7.4 QA manuel à scénariser

- Créer un paiement complet, vérifier toast et apparition liste
- Créer un paiement partiel (< loyer bail) → warning UI visible, soumission OK
- Créer un paiement avec surplus → message info visible, soumission OK
- Tenter de saisir `period_end < period_start` → erreur inline, pas d'appel Supabase
- Bail clôturé : bouton "Ajouter" désactivé + tooltip
- Soft-delete : disparition liste, vérifier en SQL que `deleted_at` est positionné
- Vérifier locale FR : `1 234,56 €` (espace insécable, virgule)

---

## 8. Risques identifiés et mitigation

| Risque | Mitigation |
|---|---|
| **Bail clôturé / archivé** : le trigger DB n'empêche pas le paiement (volontaire, cf. §2.3). Si bug UI, un paiement peut être créé sur bail terminé sans warning. | Test widget explicite + tooltip clair + tests RLS prouvent l'autorisation DB intentionnelle. |
| **Pré-remplissage stale** : si l'utilisateur modifie le bail puis ouvre le form paiement dans un autre onglet, les montants pré-remplis peuvent être obsolètes. | Pré-remplissage = simple `controller.text` initial, l'utilisateur peut toujours ajuster. UX acceptable pour MVP. |
| **Conversion float→cents** : `84.99 * 100 = 8498.999...`. Bug classique. | Déjà résolu dans `MoneyFormat.eurosToCents` via `.round()` (cf. [`money_format.dart:30`](../../lib/core/utils/money_format.dart)). Test unitaire à dupliquer côté payment. |
| **RLS bypass via landlord_id forgé** : un client malicieux pourrait passer `landlord_id` d'un autre user dans son INSERT payload. | RLS WITH CHECK `landlord_id = auth.uid()` rejette (42501) + trigger ownership rejette (23514) — défense en profondeur. |
| **Doublon de paiement** (décision produit : autorisé) | Documenter clairement dans UI : afficher tous les paiements d'une période. FEAT-007 sommera. |
| **Soft-delete leak sur FEAT-007** : si quittance pré-calcule un total mais que le paiement est soft-deleted entre-temps. | Policy SELECT filtre `deleted_at IS NULL` — la quittance ne verra pas la ligne. Acceptable. |
| **Date `paid_at` dans le futur** : prélèvement programmé. | Autorisé (bornes 1900–2100 seulement). Documenter dans le helper validator. |

---

## 9. Découpage en commits suggéré

L'agent `flutter-dev` / `supabase-dev` peut suivre ce séquencement (chaque commit doit passer `flutter analyze` + tests existants) :

1. **`feat(payments): migration + RLS + RPC soft_delete_payment`** — migration SQL (public+dev) + tests RLS dans `supabase/tests/rls_payments.sql`. Appliquée par `supabase-dev` sur Supabase avant Flutter.
2. **`refactor(core): extract money_validators`** *(optionnel mais conseillé)* — sortir `validateRentAmount`/`validateChargesAmount` de `lease_form_validators.dart` vers `lib/core/utils/money_validators.dart`. Mettre à jour les imports.
3. **`feat(payments): domain models + repository`** — `payment.dart` (freezed), `payment_method.dart`, `payment_form_state.dart`, `payment_repository.dart` (+ provider), `payment_form_validators.dart`. Tests unit `repository_test` + `validators_test`.
4. **`feat(payments): riverpod providers`** — `lease_payments_provider.dart`, `payment_detail_provider.dart`, `payment_form_controller.dart`. Pas d'UI pour l'instant.
5. **`feat(payments): UI form + list section`** — `payment_form_page.dart`, `payment_form.dart`, `payment_list_section.dart`, `payment_list_tile.dart`, `payment_amount_warning.dart`. Routes go_router. Mise à jour `lease_detail_page.dart` (remplace `_PaymentsPlaceholder` par `PaymentListSection`).
6. **`test(payments): widget + integration`** — `payment_form_test.dart`, `payment_list_section_test.dart`, `payment_archive_dialog_test.dart`.
7. **`chore(state): refresh state cache post-FEAT-006`** — `state-keeper` met à jour `docs/state/SCHEMA.md`, `ROUTES.md`, `FEATURES.md`.

PR unique vers `main` (squash merge) ou enchaînement de PRs si chaque étape est review-friendly.

---

## 10. Questions critiques à remonter avant code

**Aucune question bloquante** — toutes les décisions produit ont été tranchées dans la story ([`docs/backlog/006-payment-record.md:152-156`](../backlog/006-payment-record.md)) :
- Paiements partiels = libre + warning UI
- Doublons période = autorisés
- Distinction loyer/charges = obligatoire
- Soft-delete uniquement

**Recommandations non bloquantes** à valider par le product-owner :
1. **Pas de route `/payments` globale** dans FEAT-006 (toutes paiements multi-baux). À planifier P1 si demande utilisateur ressort en QA staging.
2. **`paid_at` autorisé dans le futur** (prélèvement programmé) — confirmer que c'est OK pour le MVP. Sinon ajouter `validatePaidAt: paidAt <= today`.
3. **Refactor `money_validators.dart`** (commit 2) — léger over-engineering pour MVP, mais évite duplication. À trancher : "oui, code partagé" vs "non, dupliquer 4 lignes pour 2 features". Recommandation : oui (lecture future plus claire).

---

## Effort estimé

- **Taille** : **M** (1.5–2.5 jours dev solo, comparable à FEAT-005 qui a livré 18 fichiers Dart + migration en effort M)
- **Fichiers créés** : ~15 Dart (+ 2 générés `.freezed.dart` + 1 `.g.dart`), 1 migration SQL, 1 fichier de tests RLS, 4 fichiers de tests Dart
- **Fichiers modifiés** : `lib/core/router/app_router.dart` (+2 routes), `lib/features/leases/presentation/lease_detail_page.dart` (remplace `_PaymentsPlaceholder` par `PaymentListSection`), `docs/state/*` (post-merge state-keeper)
- **Total touché/créé** : ~25 fichiers (cohérent avec FEAT-004 et FEAT-005)
