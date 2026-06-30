# Plan — [FEAT-017] Rentabilité locative (Portfolio Profitability v1)

## Summary

Ajouter une vision rentabilité au portefeuille : rendement brut, rendement net, cash-flow mensuel après prêt. v1 minimale = enrichir `properties` avec ~12 colonnes financières nullable (acquisition, prêt, charges annuelles), un compute engine Dart pur (`lib/core/finance/`), un widget de fiche bien `PropertyProfitabilityCard`, un KPI dashboard `PortfolioYieldKpi`, et une section "Financement" pliée par défaut dans le formulaire bien. Pas de nouvelle table — tout en colonnes scalaires sur `properties` pour limiter la complexité v1 (les scénarios multi-prêts et l'historique iront en v2 via `loan_scenarios` et `property_expenses`).

## Data model changes

### Migration

Fichier : `supabase/migrations/20260630120000_feat017_property_profitability.sql`

```sql
BEGIN;

-- ============================================================================
-- PROD (public.properties) — ajout des 12 colonnes financières (toutes NULL)
-- ============================================================================

ALTER TABLE public.properties
  ADD COLUMN purchase_price_cents          bigint,
  ADD COLUMN notary_fees_cents             bigint,
  ADD COLUMN loan_principal_cents          bigint,
  ADD COLUMN loan_rate_basis_points        integer,
  ADD COLUMN loan_duration_months          smallint,
  ADD COLUMN loan_start_date               date,
  ADD COLUMN monthly_payment_cents         bigint,
  ADD COLUMN property_tax_annual_cents     bigint,
  ADD COLUMN insurance_annual_cents        bigint,
  ADD COLUMN hoa_non_recoverable_cents     bigint,
  ADD COLUMN vacancy_rate_percent          numeric(5,2),
  ADD COLUMN maintenance_budget_percent    numeric(5,2);

ALTER TABLE public.properties
  ADD CONSTRAINT properties_purchase_price_check
    CHECK (purchase_price_cents IS NULL OR (purchase_price_cents >= 0 AND purchase_price_cents <= 1000000000000)),
  ADD CONSTRAINT properties_notary_fees_check
    CHECK (notary_fees_cents IS NULL OR (notary_fees_cents >= 0 AND notary_fees_cents <= 100000000000)),
  ADD CONSTRAINT properties_loan_principal_check
    CHECK (loan_principal_cents IS NULL OR (loan_principal_cents >= 0 AND loan_principal_cents <= 1000000000000)),
  ADD CONSTRAINT properties_loan_rate_bps_check
    CHECK (loan_rate_basis_points IS NULL OR (loan_rate_basis_points >= 0 AND loan_rate_basis_points <= 5000)),
  ADD CONSTRAINT properties_loan_duration_check
    CHECK (loan_duration_months IS NULL OR (loan_duration_months >= 0 AND loan_duration_months <= 600)),
  ADD CONSTRAINT properties_monthly_payment_check
    CHECK (monthly_payment_cents IS NULL OR (monthly_payment_cents >= 0 AND monthly_payment_cents <= 100000000)),
  ADD CONSTRAINT properties_property_tax_check
    CHECK (property_tax_annual_cents IS NULL OR (property_tax_annual_cents >= 0 AND property_tax_annual_cents <= 100000000000)),
  ADD CONSTRAINT properties_insurance_annual_check
    CHECK (insurance_annual_cents IS NULL OR (insurance_annual_cents >= 0 AND insurance_annual_cents <= 100000000000)),
  ADD CONSTRAINT properties_hoa_non_recoverable_check
    CHECK (hoa_non_recoverable_cents IS NULL OR (hoa_non_recoverable_cents >= 0 AND hoa_non_recoverable_cents <= 100000000000)),
  ADD CONSTRAINT properties_vacancy_rate_check
    CHECK (vacancy_rate_percent IS NULL OR (vacancy_rate_percent >= 0 AND vacancy_rate_percent <= 100)),
  ADD CONSTRAINT properties_maintenance_budget_check
    CHECK (maintenance_budget_percent IS NULL OR (maintenance_budget_percent >= 0 AND maintenance_budget_percent <= 100));

-- ============================================================================
-- DEV (dev.properties) — mirror exact
-- ============================================================================

ALTER TABLE dev.properties
  ADD COLUMN purchase_price_cents          bigint,
  ADD COLUMN notary_fees_cents             bigint,
  ADD COLUMN loan_principal_cents          bigint,
  ADD COLUMN loan_rate_basis_points        integer,
  ADD COLUMN loan_duration_months          smallint,
  ADD COLUMN loan_start_date               date,
  ADD COLUMN monthly_payment_cents         bigint,
  ADD COLUMN property_tax_annual_cents     bigint,
  ADD COLUMN insurance_annual_cents        bigint,
  ADD COLUMN hoa_non_recoverable_cents     bigint,
  ADD COLUMN vacancy_rate_percent          numeric(5,2),
  ADD COLUMN maintenance_budget_percent    numeric(5,2);

ALTER TABLE dev.properties
  ADD CONSTRAINT properties_purchase_price_check
    CHECK (purchase_price_cents IS NULL OR (purchase_price_cents >= 0 AND purchase_price_cents <= 1000000000000)),
  ADD CONSTRAINT properties_notary_fees_check
    CHECK (notary_fees_cents IS NULL OR (notary_fees_cents >= 0 AND notary_fees_cents <= 100000000000)),
  ADD CONSTRAINT properties_loan_principal_check
    CHECK (loan_principal_cents IS NULL OR (loan_principal_cents >= 0 AND loan_principal_cents <= 1000000000000)),
  ADD CONSTRAINT properties_loan_rate_bps_check
    CHECK (loan_rate_basis_points IS NULL OR (loan_rate_basis_points >= 0 AND loan_rate_basis_points <= 5000)),
  ADD CONSTRAINT properties_loan_duration_check
    CHECK (loan_duration_months IS NULL OR (loan_duration_months >= 0 AND loan_duration_months <= 600)),
  ADD CONSTRAINT properties_monthly_payment_check
    CHECK (monthly_payment_cents IS NULL OR (monthly_payment_cents >= 0 AND monthly_payment_cents <= 100000000)),
  ADD CONSTRAINT properties_property_tax_check
    CHECK (property_tax_annual_cents IS NULL OR (property_tax_annual_cents >= 0 AND property_tax_annual_cents <= 100000000000)),
  ADD CONSTRAINT properties_insurance_annual_check
    CHECK (insurance_annual_cents IS NULL OR (insurance_annual_cents >= 0 AND insurance_annual_cents <= 100000000000)),
  ADD CONSTRAINT properties_hoa_non_recoverable_check
    CHECK (hoa_non_recoverable_cents IS NULL OR (hoa_non_recoverable_cents >= 0 AND hoa_non_recoverable_cents <= 100000000000)),
  ADD CONSTRAINT properties_vacancy_rate_check
    CHECK (vacancy_rate_percent IS NULL OR (vacancy_rate_percent >= 0 AND vacancy_rate_percent <= 100)),
  ADD CONSTRAINT properties_maintenance_budget_check
    CHECK (maintenance_budget_percent IS NULL OR (maintenance_budget_percent >= 0 AND maintenance_budget_percent <= 100));

SELECT dev.assert_rls_both_schemas('properties');

COMMIT;
```

**Pourquoi tout nullable** : backward compatibility 100% (cohérent avec pattern FEAT-014). Les fiches existantes n'auront pas de KPI rentabilité tant que l'utilisateur n'aura pas saisi les données — affichage gracieux "Renseignez le prix d'achat pour calculer le rendement".

**Pourquoi `loan_rate_basis_points` en int** : taux en bps (3.25% = 325) évite les float et reste cohérent avec convention cents/bps EasyRent.

**Pourquoi `monthly_payment_cents` stocké** : calculable depuis principal/rate/duration mais on le cache pour :
1. Permettre une saisie manuelle (l'utilisateur lit son tableau d'amortissement bancaire qui peut inclure assurance).
2. Éviter les recalculs et incohérences si l'utilisateur renégocie son prêt.
3. Si NULL et triplet (principal, rate, duration) renseigné → fallback calculé à la volée par le compute engine.

**Pourquoi `vacancy_rate_percent` et `maintenance_budget_percent` saisis** : v1 = simulateur manuel. Le calcul auto depuis l'historique `payments` viendra en v2.

### RLS policies

**Aucune modification RLS**. Les colonnes ajoutées héritent automatiquement des policies existantes sur `properties` :
- `properties_select_own` : `landlord_id = auth.uid()`
- `properties_insert_own` : WITH CHECK `landlord_id = auth.uid()`
- `properties_update_own` : USING + WITH CHECK `landlord_id = auth.uid()`

**Modèle de menace** : ces colonnes contiennent des données financières sensibles (prix d'achat, prêt). La RLS landlord_id = auth.uid() couvre déjà strictement la confidentialité cross-user. Aucune fonction SECURITY DEFINER ne lit ces colonnes — donc pas de risque de fuite via RPC. La RGPD ne demande pas de chiffrement applicatif (au-delà du chiffrement at-rest Supabase) pour ces données.

## Backend (Edge Functions)

**N/A — aucune Edge Function.** Le compute engine vit côté client (Dart pur). Justification :
- Pas de secret ni de calcul lourd (formules d'annuité = arithmétique O(1)).
- Pas de PDF à générer (v2 si export PDF rentabilité).
- Les agrégats portefeuille (`PortfolioYieldKpi`) se calculent en Dart sur la liste des `Property` déjà chargée par Riverpod — pas de roundtrip réseau supplémentaire.

## Flutter changes

### New files

**Compute engine (Dart pur, testable)** :
- `lib/core/finance/profitability.dart` — fonctions pures :
  - `int computeLoanMonthlyPaymentCents({required int principalCents, required int rateBasisPoints, required int durationMonths})` — formule annuité fixe `P × i / (1 − (1+i)^−n)` où `i = rateBasisPoints / 10000 / 12`. Cases limites : `durationMonths == 0` → 0 ; `rateBasisPoints == 0` → `principal / duration` (prêt à taux zéro) ; `principalCents <= 0` → 0.
  - `double? computeYieldGrossPercent({required int annualRentCents, required int totalAcquisitionCents})` — `(loyer annuel / coût acquisition) × 100`. Retourne `null` si dénominateur ≤ 0.
  - `double? computeYieldNetPercent({required int annualRentCents, required int annualChargesNonRecoverableCents, required int totalAcquisitionCents})` — `((loyer annuel − charges non récup) / coût acquisition) × 100`. Charges non récup = taxe foncière + PNO + HOA non récup + (loyer annuel × maintenance_budget_percent / 100) + (loyer annuel × vacancy_rate_percent / 100). Retourne `null` si dénominateur ≤ 0.
  - `int computeMonthlyCashflowCents({required int monthlyRentCents, required int monthlyChargesNonRecoverableCents, required int monthlyLoanPaymentCents})` — peut être négatif (cash-flow négatif autorisé).
  - `ProfitabilitySnapshot computeProfitabilitySnapshot(Property p, {int? observedAnnualRentCents})` — agrège tout en un objet immuable freezed.
- `lib/core/finance/profitability_snapshot.dart` — modèle freezed `ProfitabilitySnapshot` (totalAcquisitionCents, monthlyLoanPaymentCents, yieldGrossPercent, yieldNetPercent, monthlyCashflowCents, isComplete, missingFields).
- `lib/core/finance/profitability_snapshot.freezed.dart` — généré.

**Widgets** :
- `lib/features/properties/presentation/widgets/property_profitability_card.dart` — section "Rentabilité" dans `property_detail_page.dart`. Affiche : rendement brut, rendement net, mensualité prêt, cash-flow mensuel. Si données incomplètes → CTA "Compléter les informations financières" (deep-link `/properties/:id/edit#financing`).
- `lib/features/dashboard/presentation/widgets/portfolio_yield_kpi.dart` — KPI dashboard : rendement brut moyen pondéré (par valeur d'acquisition) + cash-flow agrégé du portefeuille. Réutilise `KpiCard` existant. Affiché uniquement si au moins 1 propriété a `purchase_price_cents IS NOT NULL`.

**Domain** :
- Étendre `lib/features/properties/domain/property.dart` (freezed) avec les 12 nouveaux champs nullable + helpers `@JsonKey(name: '...')` snake_case. Re-run `build_runner` après.

**Application (Riverpod)** :
- `lib/features/properties/application/property_profitability_provider.dart` — `family<ProfitabilitySnapshot, String>` par propertyId. Lit la `Property` + le loyer du bail actif courant via `activeLeaseForPropertyProvider` (à créer si absent, ou inlined).
- `lib/features/dashboard/application/portfolio_yield_provider.dart` — agrège tous les `ProfitabilitySnapshot` du portefeuille (rendement moyen pondéré + cash-flow total).

### Modified files

- `lib/features/properties/domain/property.dart` — ajouter les 12 champs (cf. ci-dessus).
- `lib/features/properties/data/property_repository.dart` — ajouter les nouveaux champs dans `insertProperty()` et `updateProperty()` (payload UPDATE). Aucun changement pour le SELECT (Supabase retourne tout par défaut).
- `lib/features/properties/presentation/widgets/property_form.dart` — ajouter `ExpansionTile` "Financement" (initiallyExpanded: false). Champs :
  - Prix d'achat (`purchase_price_cents`, en euros, conversion ×100).
  - Frais de notaire (`notary_fees_cents`).
  - Sous-section "Prêt immobilier" : capital emprunté, taux (en %, conversion ×100 pour bps), durée (mois), date début, mensualité (calculée auto si vide, surchargeable manuelle).
  - Sous-section "Charges annuelles" : taxe foncière, assurance PNO, charges copro non récupérables.
  - Sous-section "Hypothèses" : taux de vacance (%), budget travaux (%) — préremplis avec 5% et 5%.
- `lib/features/properties/presentation/property_form_page.dart` — passer les 12 nouveaux controllers/states au widget `PropertyForm` et sauvegarder via repository.
- `lib/features/properties/presentation/property_detail_page.dart` — insérer `<PropertyProfitabilityCard property={property} />` après `_InfoCard`.
- `lib/features/dashboard/presentation/dashboard_page.dart` — insérer `PortfolioYieldKpi` dans `KpiGrid` (conditionnel sur présence de données).
- `lib/features/dashboard/domain/dashboard_kpi.dart` — ajouter classe freezed `PortfolioYieldKpi({required double? grossYieldWeightedAvgPercent, required int monthlyCashflowAggregatedCents, required int propertiesWithDataCount, required int propertiesTotalCount})`.
- `lib/core/utils/property_form_validators.dart` — ajouter validators pour cents (>= 0, <= 1e12), pour bps (0–5000), pour percent (0–100), pour durée mois (0–600).
- `docs/state/SCHEMA.md` — documenter les 12 nouvelles colonnes (post-implémentation, par `state-keeper`).
- `docs/state/FEATURES.md` — entrée FEAT-017.

### Providers

- `propertyProfitabilityProvider(propertyId)` — `FutureProvider.family<ProfitabilitySnapshot, String>`.
- `portfolioYieldProvider` — `FutureProvider<PortfolioYieldKpi>` (dépend de `propertiesListProvider` + leases actifs).
- (Réutilise) `propertyDetailProvider`, `propertiesListProvider`, `dashboardProvider`.

### Routes

Aucune nouvelle route. Tout passe par les routes existantes :
- `/properties/:id` → ajoute section Rentabilité.
- `/properties/:id/edit` → ajoute section "Financement" (anchor `#financing` pour futur scroll).
- `/` → ajoute KPI Portfolio yield.

## Testing strategy

### Unit tests (compute engine — priorité haute)

- `test/core/finance/profitability_test.dart` :
  - `computeLoanMonthlyPaymentCents` :
    - Cas nominal : 200 000€ à 3.25% sur 240 mois → ~113 760 cents/mois (±1 cent tolérance).
    - Taux 0% : `principal / duration` exact.
    - Durée 0 : retourne 0 (pas de division par 0).
    - Principal 0 ou négatif : retourne 0.
    - Très long terme (600 mois) : pas d'overflow int (vérifier que `Math.pow` reste stable).
  - `computeYieldGrossPercent` : nominal, dénominateur 0 → null, dénominateur négatif → null.
  - `computeYieldNetPercent` : nominal, soustraction des charges, vacancy + maintenance budget appliqués.
  - `computeMonthlyCashflowCents` : positif, négatif, zéro.
  - `computeProfitabilitySnapshot` : `isComplete=false` si purchase_price NULL, `missingFields` liste correcte.

### Widget tests

- `test/features/properties/presentation/widgets/property_profitability_card_test.dart` — affichage CTA si données manquantes, affichage valeurs si complètes.
- `test/features/dashboard/presentation/widgets/portfolio_yield_kpi_test.dart` — masqué si 0 property avec data, affiché sinon.

### RLS tests

**Pas de nouveau test RLS** : aucune nouvelle policy, aucune nouvelle table. Les colonnes héritent de la RLS existante de `properties` couverte par `supabase/tests/rls_properties.sql` (12 tests).

### Manual QA scenarios

1. Créer un bien sans champs financiers → fiche détail affiche CTA "Renseignez le prix d'achat".
2. Compléter prix + notaire uniquement → rendement brut calculé, rendement net affiche "Renseignez les charges annuelles".
3. Compléter prêt → cash-flow mensuel calculé. Vérifier mensualité auto = mensualité bancaire ±1€.
4. Saisir mensualité manuelle → override auto-calcul.
5. Cross-user : créer un bien financier sous user A, vérifier que user B ne voit ni la fiche ni les KPI.
6. Dashboard : 0 bien avec data → KPI masqué. 1 bien avec data → KPI visible.
7. Forms : taux > 50% (5000 bps) refusé. Durée 700 mois refusée.
8. Backward compat : ouvrir un bien créé avant FEAT-017 → tous les champs financiers à NULL, pas d'erreur.

## Risks

- **Risque 1 — Précision arithmétique formule annuité** : `Math.pow((1+i), n)` en double sur 240–360 mois peut perdre quelques cents. Atténuation : tolérance ±1 cent dans les tests, et permettre l'override manuel `monthly_payment_cents`.
- **Risque 2 — Cas limite taux 0%** : la formule générale divise par `(1 − (1+i)^−n) = 0` quand i=0. Branchement explicite obligatoire dans le compute engine.
- **Risque 3 — Form qui devient trop long** : déjà 3 sections existantes + 1 nouvelle = 4 ExpansionTile. Atténuation : "Financement" pliée par défaut + ordre logique (saisie progressive non bloquante).
- **Risque 4 — Aucune validation cross-field au DB level** : ex. `loan_principal_cents > purchase_price_cents` est techniquement autorisé (rachat de soulte, etc.). On laisse passer en v1, on documente. Pas de check DB.
- **Risque 5 — Rendement brut interprété comme conseil fiscal** : ajouter mention "Estimation indicative — consultez un expert-comptable" sous le widget rentabilité. Pas un produit financier réglementé, mais prudence.
- **Risque 6 — Le compute engine ignore le régime fiscal** : v1 = rendement avant impôt. Documenter clairement "Rendement brut/net avant impôt sur le revenu et prélèvements sociaux". v2 ajoutera `tax_regime`.
- **Risque 7 — Le loyer annuel utilisé** : v1 lit `rent_amount_cents × 12` du bail actif. Si la propriété est vacante (pas de bail actif) → loyer = 0 → rendement = 0%. Affichage spécifique "Bien vacant — rentabilité non calculable".

## Step-by-step execution order

1. **Migration SQL** via `supabase-dev` : appliquer `20260630120000_feat017_property_profitability.sql` en dev + prod.
2. **Compute engine** via `flutter-dev` :
   1. Créer `lib/core/finance/profitability_snapshot.dart` (freezed) + `profitability.dart` (fonctions pures).
   2. Lancer `build_runner` pour générer les `.freezed.dart`.
   3. Écrire les unit tests dans `test/core/finance/profitability_test.dart`.
3. **Domain** via `flutter-dev` : étendre `Property` freezed avec les 12 champs + regénérer.
4. **Repository** via `flutter-dev` : étendre `property_repository.dart` (insert + update payload).
5. **Forms** via `flutter-dev` : ajouter section "Financement" dans `property_form.dart` + controllers dans `property_form_page.dart`.
6. **Widgets détail** via `flutter-dev` : créer `PropertyProfitabilityCard` + intégrer dans `property_detail_page.dart`.
7. **Dashboard** via `flutter-dev` : créer `PortfolioYieldKpi` widget + provider + KPI freezed model + intégrer dans `dashboard_page.dart`.
8. **Tests** via `qa-tester` : unit tests compute engine, widget tests, smoke test cross-user.
9. **Review** via `code-reviewer` + `security-auditor` :
   - Vérifier que les champs financiers n'apparaissent dans aucun log ni payload non-RLS.
   - Vérifier formatage `fr_FR` (séparateur milliers `1 234,56 €`).
   - Vérifier `flutter analyze` clean + `dart format`.
10. **State refresh** via `state-keeper` : MAJ `SCHEMA.md`, `FEATURES.md`, `INDEX.md`.
11. **Deploy staging** : merger dans `develop` → auto-deploy Firebase Hosting staging.
12. **Validation produit** : démo à l'utilisateur avant push prod.

## Out of scope (v2+)

- Table `loan_scenarios` (multi-prêts, simulation).
- Table `property_expenses` (charges ponctuelles datées).
- Champ `tax_regime` + simulateur fiscal (micro-foncier vs réel, abattement 30%/50% LMNP).
- Plus-value latente (`current_market_value_cents`).
- TRI (Taux de Rendement Interne).
- Taux d'occupation calculé depuis l'historique réel (vs hypothèse saisie).
- Export PDF rapport rentabilité.
- Graphes (évolution rendement vs marché).
