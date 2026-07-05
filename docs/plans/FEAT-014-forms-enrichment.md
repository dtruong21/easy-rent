# Plan — FEAT-014 — Forms enrichment pour conformité location FR (MVP)

> Designé par architect le 2026-06-22. À démarrer après merge FEAT-013 Phase 2 UX (palette indigo).

## 1. Vue d'ensemble

User feedback : formulaires Property/Tenant/Lease/Payment manquent d'informations attendues par un bailleur français (DPE, dépôt de garantie, lease_type, profession locataire, IRL, etc.).

**Niveau cible MVP utilisable** — champs courants sans détails fins (lot copro, n° sécu).

**Décomposition en 4 sous-phases** :

| Phase | Entité | Branche | Champs | Effort |
|---|---|---|---|---|
| 1 | Property | `feature/feat-014-phase1-property` | 12 cols (DPE/GES, étage, meublé, chauffage, postal/city) | ~5h |
| 2 | Tenant | `feature/feat-014-phase2-tenant` | 10 cols (naissance, profession, revenus, garant) | ~4h |
| 3 | Lease | `feature/feat-014-phase3-lease` | 9 cols (lease_type, deposit, IRL, payment_day, solidarité) | ~6h |
| 4 | Payment | `feature/feat-014-phase4-payment` | 1 col (`reference`) + audit | ~1h30 |

**Total** : ~16h30. **Ordre** : 1 → 2 → 3 → 4. Démarrer **après** merge FEAT-013 Phase 2 UX.

## 2. Décisions verrouillées (transverses)

| Sujet | Décision |
|---|---|
| Validation enums | CHECK constraint côté DB + validateur client |
| Format `irl_quarter_ref` | text libre `^T[1-4]-\d{4}$` (ex: `T1-2026`) |
| `nationality` | text libre |
| DPE letter / value | indépendants nullable |
| `monthly_income_cents` | bigint |
| `construction_year` | smallint 1700..(now+1) |
| Sentinel "non communiqué" | NULL |
| `solidarity_clause` | bool sur lease (MVP 1-tenant) |
| `payment_method` sur lease | réutilise enum `payments.payment_method` (`virement`/`cheque`/`especes`/`prelevement`/`autre`) |
| `lease_type` enum | `unfurnished`/`furnished`/`mobility`/`student` (default `unfurnished`) |
| `payment_day` | int 1..28 |
| `postal_code`/`city` | nullable, séparés de `address` |
| `birth_date` | date CHECK `≥1900 AND ≤now()-18ans` |
| Backward compat | tous nouveaux nullable ou DEFAULT |

## 3. Phase 1 — Property (~5h)

### Colonnes ajoutées
- `rooms` smallint CHECK >0, ≤50
- `bedrooms` smallint CHECK ≥0, ≤50
- `floor` smallint CHECK -5..200
- `has_elevator` bool DEFAULT false
- `furnished` bool DEFAULT false
- `heating_type` text CHECK ∈ ('electric','gas','collective','fuel','wood','heat_pump','other')
- `dpe_letter` text CHECK `^[A-G]$`
- `dpe_value_kwh_m2_year` int CHECK 1..1999
- `ges_letter` text CHECK `^[A-G]$`
- `construction_year` smallint CHECK 1700..(now+1)
- `postal_code` text CHECK `^\d{5}$`
- `city` text CHECK length 1..100

### Form UI — 3 sections
1. Informations principales (existant) + postal_code/city
2. Caractéristiques (ExpansionTile fermée) : pièces/chambres/étage/ascenseur/meublé/chauffage/année
3. Diagnostic énergétique (ExpansionTile fermée) : DPE letter+value, GES letter

### Fichiers
- Nouveau : `lib/features/properties/domain/heating_type.dart`
- Migration : `supabase/migrations/<ts>_feat014_phase1_property_enrichment.sql`
- Modifier : `property.dart`, `property_repository.dart`, `property_form.dart`, `property_form_validators.dart`
- Tests : `property_serialization_test.dart`, `property_form_validators_test.dart`, étendre form test

## 4. Phase 2 — Tenant (~4h)

### Colonnes ajoutées
- `birth_date` date CHECK `≥1900 AND ≤now()-18ans`
- `birth_place` text
- `nationality` text
- `profession` text
- `employer` text
- `monthly_income_cents` bigint CHECK 0..10G
- `previous_address` text
- `guarantor_name` text
- `guarantor_email` text CHECK regex email
- `guarantor_phone` text

### Form UI — 3 sections
1. Identité (existant) + birth_date/birth_place/nationality
2. Situation professionnelle (ExpansionTile) : profession/employer/revenus/adresse précédente
3. Garant (ExpansionTile) : nom/email/phone

### Fichiers
- Migration : `supabase/migrations/<ts>_feat014_phase2_tenant_enrichment.sql`
- Modifier : `tenant.dart`, `tenant_repository.dart`, `tenant_form.dart`, validators
- Refactor opportuniste : extraire `_dateFromJson`/`_dateToJson` dans `core/utils/json_date.dart`

## 5. Phase 3 — Lease (~6h, le plus complexe)

### Colonnes ajoutées
- `lease_type` text DEFAULT `unfurnished` CHECK ∈ enum
- `deposit_amount_cents` bigint CHECK 0..10G
- `payment_day` smallint DEFAULT 1 CHECK 1..28
- `payment_method` text DEFAULT `virement` CHECK ∈ enum (réutilise payments)
- `irl_index_value` numeric(8,2) CHECK >0, <10000
- `irl_quarter_ref` text CHECK `^T[1-4]-\d{4}$`
- `agency_fees_cents` bigint DEFAULT 0 CHECK ≥0
- `solidarity_clause` bool DEFAULT false
- `entry_inventory_done` bool DEFAULT false

### Form UI — 5 sections
1. Parties et bien (existant)
2. Loyer et charges + dépôt + honoraires
3. Type de bail (Dropdown avec helperText durée légale dynamique) + dates
4. Modalités paiement (ExpansionTile) : jour + mode
5. IRL et clauses (ExpansionTile) : valeur IRL + trimestre + solidarité + état des lieux

### Fichiers
- Nouveau : `lib/features/leases/domain/lease_type.dart` (avec `legalMinDurationMonths`)
- Refactor : `core/utils/payment_method_json.dart` (partagé)
- Migration : `supabase/migrations/<ts>_feat014_phase3_lease_enrichment.sql`
- Modifier : `lease.dart`, `lease_repository.dart`, `lease_form.dart`, validators

### UX detail
HelperText dynamique sur dépôt de garantie selon `lease_type` :
- `unfurnished` : "Bail vide : DG max légal = 1 mois HC"
- `furnished` : "Bail meublé : DG max légal = 2 mois HC"
- Info, pas blocage.

## 6. Phase 4 — Payment audit (~1h30)

`payment_method` déjà présent. Manque juste :
- `reference` text CHECK length 1..100 (n° virement/chèque pour rapprochement)

Migration triviale + form ajout TextFormField optionnel.

## 7. Risques globaux

1. **Build_runner freezed @Default strict** : tester après chaque sous-phase
2. **Forms trop longs** : ExpansionTile fermées par défaut, helper "Optionnel" partout
3. **Désynchro enum SQL/Dart** : `fromSql()` avec fallback `otherwise`
4. **Conflit Git FEAT-013 Phase 2** : merger Phase 2 UX d'abord
5. **`payment_method` dupliqué lease/payment** : sémantique distincte (attendu vs constaté). Acceptable.
6. **`furnished` (property) vs `lease_type=furnished` (lease)** : décision actée — coexistent (état physique vs qualification juridique)
7. **Migration scan complet** : tables petites, acceptable. Si scale > 1M lignes, basculer `NOT VALID + VALIDATE`

## 8. Ordre d'exécution

1. **FEAT-013 Phase 2 UX merge** (palette indigo, en cours)
2. **FEAT-014 Phase 1 (Property)** — pattern le plus simple
3. **FEAT-014 Phase 2 (Tenant)** — pattern rodé
4. **FEAT-014 Phase 3 (Lease)** — le plus complexe + refactor opportuniste payment_method_json
5. **FEAT-014 Phase 4 (Payment)** — petite phase de finition

Chaque sous-phase :
- Sa migration `supabase db push --linked`
- Son PR isolée
- analyze + format + tests verts avant push
- code-reviewer + security-auditor avant merge

## 9. Hors scope MVP (backlog)

- Calculateur loyer encadré zones tendues
- Upload PDF DPE (lié FEAT-009)
- Lot cadastral/copro
- N° sécurité sociale
- Calcul auto IRL trimestriel (cron INSEE API)
- Multi-tenants colocation propre
- Génération bail PDF avec nouveaux champs
- Géocodage `address` → `postal_code`/`city` (BAN API)

## 10. Critical risks à valider PO

1. **Duplication `furnished` (property) vs `lease_type` (lease)** — sémantique distincte, acceptable mais confirmer
2. **9 colonnes nouvelles sur Lease** — forms longs, ExpansionTile mitigeant. Confirmer que `agency_fees_cents` utile pour bailleur particulier
3. **`payment_method` stocké deux fois** (lease + payment) sans contrainte de cohérence
4. **DPE letter sans value (et inverse)** accepté — conforme réalité terrain
