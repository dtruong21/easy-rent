# Plan — [FEAT-018] Simulateur de rentabilité locative

## Summary

Page autonome `/simulator` permettant de simuler la rentabilité d'un projet d'investissement
locatif (bien existant ou hypothétique) avec form temps réel + graphique cash-flow année par année.
Sauvegarde optionnelle de scénarios nommés dans une nouvelle table `investment_scenarios`
(JSONB pour flexibilité du contrat) sous RLS landlord. **Réutilise intégralement le module
`lib/core/finance/` créé en FEAT-017** (rendements, cash-flow, amortissement, fiscalité).
Pas de couplage avec `properties` réelles — un scénario est purement spéculatif.

## DEPENDS_ON

**Critique — FEAT-017 doit être mergée d'abord** :
- Module `lib/core/finance/` : moteurs purs de calcul (rendement brut/net, amortissement,
  cash-flow, fiscalité micro/réel). Sans ce module, FEAT-018 doit re-implémenter toute la logique.
- Types canoniques `LoanParams`, `FiscalRegime`, `PropertyFinancials` (sortie attendue FEAT-017).
- Décision data model `loan_scenarios` (FEAT-017) : on s'aligne sur le même schéma JSONB.

Si FEAT-017 n'est pas finalisée au moment du démarrage FEAT-018 → produit-owner doit trancher :
soit attendre, soit forker un mini-module finance local (dette technique à rembourser).

## Data model changes

### Migration (public + dev — dual schema mandatory per CLAUDE.md)

```sql
-- supabase/migrations/<ts>_feat018_investment_scenarios.sql

-- =====================
-- PUBLIC schema
-- =====================
CREATE TABLE public.investment_scenarios (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id     uuid NOT NULL DEFAULT auth.uid()
                       REFERENCES public.landlords(id) ON DELETE RESTRICT,
  name            text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  scenario_json   jsonb NOT NULL,           -- contrat versionné, voir Annexe A
  schema_version  smallint NOT NULL DEFAULT 1 CHECK (schema_version > 0),
  notes           text NULL CHECK (notes IS NULL OR char_length(notes) <= 2000),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz NULL          -- soft-delete via RPC uniquement
);

CREATE INDEX idx_public_investment_scenarios_landlord
  ON public.investment_scenarios (landlord_id, deleted_at);

ALTER TABLE public.investment_scenarios ENABLE ROW LEVEL SECURITY;

-- RLS : scope landlord (cf. section RLS)

-- Triggers tr_00/01/02 standard (réutilise prevent_protected_columns_change + set_updated_at)
CREATE TRIGGER tr_01_prevent_protected_columns_change_investment_scenarios
  BEFORE INSERT OR UPDATE ON public.investment_scenarios
  FOR EACH ROW EXECUTE FUNCTION public.prevent_protected_columns_change();

CREATE TRIGGER tr_02_set_updated_at_investment_scenarios
  BEFORE UPDATE ON public.investment_scenarios
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Soft-delete RPC
CREATE OR REPLACE FUNCTION public.soft_delete_investment_scenario(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.allow_deleted_at_change', '1', true);
  UPDATE public.investment_scenarios
     SET deleted_at = now()
   WHERE id = p_id
     AND landlord_id = auth.uid()
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Scenario not found or already deleted'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.soft_delete_investment_scenario(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.soft_delete_investment_scenario(uuid) TO authenticated;

-- =====================
-- DEV schema (identical mirror — required per docs/ENVIRONMENTS.md)
-- =====================
CREATE TABLE dev.investment_scenarios ( ... );  -- même structure
-- + index, RLS, triggers, RPC dev.soft_delete_investment_scenario()
```

### RLS policies

```sql
CREATE POLICY investment_scenarios_select_own
  ON public.investment_scenarios FOR SELECT
  USING (landlord_id = auth.uid() AND deleted_at IS NULL);

CREATE POLICY investment_scenarios_insert_own
  ON public.investment_scenarios FOR INSERT
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY investment_scenarios_update_own
  ON public.investment_scenarios FOR UPDATE
  USING (landlord_id = auth.uid() AND deleted_at IS NULL)
  WITH CHECK (landlord_id = auth.uid());

-- Pas de policy DELETE : soft-delete via RPC uniquement.
```

**Threat model** :
- Un landlord ne voit que ses propres scénarios (SELECT/UPDATE filtrés par `auth.uid()`).
- Aucune donnée cross-tenant : pas de FK vers `properties`/`tenants` (scénarios purement
  spéculatifs). Si on ajoute plus tard `property_id` optionnel, RLS doit valider que
  `property.landlord_id = auth.uid()` via trigger `tr_00_assert_scenario_property_ownership`.
- `scenario_json` est opaque côté DB — la validation du contenu est responsabilité Flutter
  (validators + types). Pas de risque injection SQL (JSONB est typé).
- Limites de taille : `name <= 120` chars, `notes <= 2000`. JSONB sans plafond explicite
  car structure connue ~2 KB max. Ajout optionnel : `CHECK (octet_length(scenario_json::text) <= 16384)`.

### Annexe A — contrat `scenario_json` (schema_version=1)

```json
{
  "inputs": {
    "property": {
      "purchase_price_cents": 25000000,
      "notary_fees_cents": 1800000,
      "agency_fees_acquisition_cents": 0,
      "works_initial_cents": 500000,
      "surface_m2": 45.0,
      "city": "Paris",
      "postal_code": "75011"
    },
    "rental": {
      "monthly_rent_cents": 95000,
      "monthly_charges_cents": 5000,
      "vacancy_pct": 4.0,
      "property_tax_annual_cents": 80000,
      "insurance_pno_annual_cents": 15000,
      "condo_fees_annual_cents": 120000,
      "condo_fees_recoverable_pct": 60.0,
      "management_fees_pct": 0.0
    },
    "loan": {
      "principal_cents": 22000000,
      "down_payment_cents": 5300000,
      "interest_rate_bps": 325,
      "insurance_rate_bps": 35,
      "duration_months": 240,
      "start_date": "2026-09-01"
    },
    "tax": {
      "regime": "micro_foncier",
      "marginal_tax_rate_bps": 3000,
      "social_contributions_bps": 1720
    },
    "projection": {
      "horizon_years": 20,
      "rent_indexation_pct": 1.5,
      "property_appreciation_pct": 2.0
    }
  }
}
```

**Pourquoi JSONB et pas colonnes typées ?**
- Le contrat va évoluer (FEAT-017 lui-même va probablement itérer sur les champs).
- Flexibilité d'ajouter charges custom sans migration.
- `schema_version` permet migration progressive côté Flutter (read-time).
- Trade-off accepté : pas de query SQL fine-grained (acceptable pour un simulateur qui
  charge le scenario entier en mémoire).

## Backend (Edge Functions)

**N/A**. Tous les calculs sont des fonctions pures Dart (module `lib/core/finance/` issu de
FEAT-017). Pas de secrets, pas d'I/O externe. Calcul instantané côté client → UX live.

## Flutter changes

### New files

```
lib/features/simulator/
├── data/
│   └── scenario_repository.dart           # CRUD Supabase + mapping JSONB ↔ ScenarioInputs
├── domain/
│   ├── scenario.dart                      # freezed — id, name, inputs, createdAt, ...
│   ├── scenario.freezed.dart
│   ├── scenario.g.dart                    # toJson/fromJson
│   ├── scenario_inputs.dart               # freezed — inputs du formulaire (property/rental/loan/tax/projection)
│   ├── scenario_inputs.freezed.dart
│   ├── scenario_inputs.g.dart
│   ├── scenario_results.dart              # freezed — outputs calculés (KPIs + tableau annuel)
│   ├── scenario_results.freezed.dart
│   ├── annual_projection_row.dart         # 1 année : year, gross_rent, expenses, loan_interest, loan_principal, tax, cashflow, ...
│   └── annual_projection_row.freezed.dart
├── application/
│   ├── scenario_form_controller.dart      # StateNotifier<ScenarioInputs> — debounced recompute
│   ├── scenario_results_provider.dart     # Provider<ScenarioResults> — pure, dérive de form state
│   ├── scenarios_list_provider.dart       # AsyncNotifier — liste scénarios sauvegardés
│   └── scenario_detail_provider.dart      # AsyncNotifier(scenarioId) — édition d'un scénario existant
└── presentation/
    ├── simulator_page.dart                # /simulator — création (form vide ou pré-rempli)
    ├── simulator_edit_page.dart           # /simulator/:id — édition (load + save)
    ├── widgets/
    │   ├── scenario_form.dart             # Form principal — sections collapsibles
    │   ├── section_property_inputs.dart   # bloc acquisition (prix, frais, surface…)
    │   ├── section_rental_inputs.dart     # bloc loyer + charges
    │   ├── section_loan_inputs.dart       # bloc prêt
    │   ├── section_tax_inputs.dart        # bloc fiscalité (régime + TMI)
    │   ├── section_projection_inputs.dart # bloc projection (horizon, indexation)
    │   ├── results_kpi_grid.dart          # 4-6 KPI cards : rendement brut/net, cash-flow, TRI, plus-value, point mort
    │   ├── results_comparison_table.dart  # tableau annuel : année / loyer / charges / mensualité / cash-flow net / fiscal
    │   ├── results_cashflow_chart.dart    # fl_chart LineChart — cash-flow cumulé année par année
    │   ├── save_scenario_dialog.dart      # popup nom + notes pour sauvegarde
    │   └── scenarios_drawer.dart          # liste scénarios sauvegardés (sidebar/drawer)
```

### Modified files

- `lib/core/router/app_router.dart` — ajoute 2 routes (cf. Routes).
- `lib/core/ui/app_bar/app_app_bar.dart` (potentiellement) — ajouter entrée menu "Simulateur".
- `lib/features/dashboard/presentation/dashboard_page.dart` — ajouter raccourci vers
  `/simulator` (carte ou bouton, optionnel selon design).
- `docs/state/SCHEMA.md`, `docs/state/ROUTES.md`, `docs/state/FEATURES.md` — sync par state-keeper.
- `docs/CONVENTIONS.md` — si on introduit un pattern "JSONB-backed scenario", documenter.

### Providers (Riverpod)

```dart
// Form state — debounced
final scenarioFormControllerProvider =
    StateNotifierProvider.autoDispose<ScenarioFormController, ScenarioInputs>(...);

// Pure derivation — recalcule à chaque change du form
final scenarioResultsProvider =
    Provider.autoDispose<ScenarioResults>((ref) {
      final inputs = ref.watch(scenarioFormControllerProvider);
      return FinanceEngine.computeScenario(inputs);  // ← module FEAT-017
    });

// Liste scénarios sauvegardés (page principale + drawer)
final scenariosListProvider = AsyncNotifierProvider<ScenariosListNotifier, List<Scenario>>(...);

// Édition d'un scénario existant
final scenarioDetailProvider =
    AsyncNotifierProvider.autoDispose.family<ScenarioDetailNotifier, Scenario, String>(...);

// Repository
final scenarioRepositoryProvider = Provider<ScenarioRepository>(...);
```

### Routes (go_router)

| Path | Widget | Auth | Transition |
|---|---|---|---|
| `/simulator` | `SimulatorPage` | ✅ | standard |
| `/simulator/:id` | `SimulatorEditPage` | ✅ | standard |

**Note** : pas de route `/simulator/new` — `/simulator` sert à la fois pour création vierge et
calcul sans sauvegarde. Le bouton "Enregistrer" ouvre `SaveScenarioDialog`. Après save, redirect
vers `/simulator/:id` (édition).

## Compute engine (`lib/core/finance/` — FEAT-017)

Module pur Dart **déjà créé en FEAT-017**. FEAT-018 ne fait que le consommer.

**Fonctions attendues** (contrat FEAT-017 → confirmer avec architect FEAT-017) :
- `FinanceEngine.computeGrossYield(purchase, rental) → double` (rendement brut %)
- `FinanceEngine.computeNetYield(purchase, rental, expenses) → double` (rendement net %)
- `FinanceEngine.computeMonthlyLoanPayment(LoanParams) → Money` (mensualité PI + assurance)
- `FinanceEngine.computeLoanAmortization(LoanParams) → List<AmortizationRow>` (capital/intérêts mois)
- `FinanceEngine.computeAnnualCashFlow(ScenarioInputs, year) → Money` (cash-flow net mensuel × 12 - mensualité × 12 - charges - impôts)
- `FinanceEngine.computeTaxableIncome(rental, regime, expenses) → Money` (revenu imposable selon micro-foncier / réel / micro-BIC)
- `FinanceEngine.computeIRR(initialOutflow, annualCashFlows, terminalValue) → double` (TRI Newton-Raphson)
- `FinanceEngine.projectScenario(ScenarioInputs) → List<AnnualProjectionRow>` (horizon × inputs)

→ Si certaines de ces fonctions ne sont pas livrées par FEAT-017, c'est une question pour
l'architect FEAT-017 (cf. openQuestions).

## Testing strategy

### Unit tests (test/features/simulator/)
- `scenario_inputs_test.dart` : validations form (rent > 0, duration > 0, regime valide, TMI ∈ [0, 4500])
- `scenario_repository_test.dart` : roundtrip JSONB ↔ ScenarioInputs (schema_version=1)
- `scenario_form_controller_test.dart` : debounce + state transitions
- `scenario_results_provider_test.dart` : couvre 3 scénarios canoniques (Paris/Lyon/province)
  avec golden values (ex: Paris 250k€, 950€/mois, 240 mois 3.25% → rendement brut 4.56%, etc.)

### Widget tests
- `simulator_page_test.dart` : form rendu, change input → results updated
- `results_kpi_grid_test.dart` : tous les KPIs s'affichent avec valeur formatée FR
- `results_cashflow_chart_test.dart` : 20 années de data, axes corrects
- `save_scenario_dialog_test.dart` : validation name (1-120 chars)
- `simulator_edit_page_test.dart` : load scenario by ID, edit, save → toast confirm

### RLS tests (supabase/tests/rls_investment_scenarios.sql)
Pattern identique à `rls_payments.sql` (~15 tests) :
- INSERT avec landlord_id correct → OK
- INSERT avec landlord_id d'un autre user → bloqué
- SELECT cross-user → 0 rows
- UPDATE cross-user → 0 rows affected
- DELETE direct → policy absente, soft-delete RPC requis
- RPC `soft_delete_investment_scenario` avec id étranger → P0002

### Manual QA scenarios
1. Créer scénario vierge `/simulator` → form vide, KPIs à 0 → remplir prix + loyer → KPIs live.
2. Tweak taux d'intérêt prêt → cash-flow chart se met à jour < 200 ms.
3. Save scénario "T2 Paris 11e" → toast + redirect `/simulator/:id`.
4. Ouvrir scénario depuis drawer → inputs pré-remplis → modifier nom + 1 champ → save → updated_at change.
5. Supprimer scénario (soft-delete) → disparaît de la liste, n'est plus accessible.
6. Cross-user : login user B → ne voit pas le scénario user A (RLS).
7. Mobile : form scrollable, chart responsive, drawer accessible.
8. PWA offline : page reste fonctionnelle (calculs locaux), save offline → erreur user-friendly.

## Risks

- **Risque #1 — Dépendance FEAT-017 bloquante** : si FEAT-017 livre un contrat incomplet (ex:
  pas de fonction TRI ou amortissement), FEAT-018 doit forker. Mitigation : coordination entre
  les deux plans avant le sprint, ou démarrer un mini-engine local et le migrer après.

- **Risque #2 — Complexité fiscale française** : régimes micro-foncier (abatt. 30%), réel,
  micro-BIC (50%), LMNP (amortissement comptable), LMP. Faire LMNP/LMP correctement = scope
  énorme. Mitigation **MVP** : se limiter à `micro_foncier` + `reel` + `micro_bic` simplifiés.
  LMNP avec amortissement = phase 2.

- **Risque #3 — JSONB versioning** : si schema_version=2 introduit un champ obligatoire, la
  lecture des scénarios v1 doit avoir des defaults. Pattern : Dart factory `Scenario.fromJson`
  avec migration explicite par version. Tester roundtrip v1 → v2.

- **Risque #4 — UX form long** : 20+ champs peuvent décourager. Mitigation : sections
  collapsibles + valeurs par défaut intelligentes (frais notaire = 8% du prix, vacance = 4%, etc.).

- **Risque #5 — Précision flottants** : calculs financiers en `double` cumulent erreurs sur 20 ans.
  Mitigation : tous les montants en `int cents` (cohérent FEAT-014), pourcentages en `bps` ou
  `Decimal` (package `decimal` si nécessaire). Tests golden values arrondis au centime.

- **Risque #6 — Conseil fiscal non agréé** : un simulateur peut être interprété comme conseil.
  Mitigation : disclaimer obligatoire dans l'UI ("Simulation indicative, ne constitue pas un
  conseil financier ou fiscal. Consultez un professionnel."). À valider par product-owner.

- **Risque #7 — Lien avec `properties` réelles** : si user veut simuler à partir d'un bien existant,
  pas de route prévue en MVP. Acceptable : copier-coller manuel. Phase 2 = bouton "Importer depuis
  property X" dans `SimulatorPage`.

- **Risque #8 — Performance recompute** : sur 20 ans × 12 mois = 240 lignes d'amortissement +
  20 lignes projection à chaque keystroke. Mitigation : debounce 200-300ms sur form controller,
  `Provider.autoDispose` pour invalidation propre.

## Step-by-step execution order

1. **Prérequis** : FEAT-017 mergée sur develop (module `lib/core/finance/` disponible).
2. **Migration SQL** via `supabase-dev` : table `investment_scenarios` + RLS + RPC sur public **et** dev.
3. **RLS tests** via `qa-tester` : `supabase/tests/rls_investment_scenarios.sql` (~15 tests).
4. **Domain layer Flutter** via `flutter-dev` : freezed models (`Scenario`, `ScenarioInputs`,
   `ScenarioResults`, `AnnualProjectionRow`) + `build_runner`.
5. **Data layer** : `ScenarioRepository` (CRUD via Supabase client) + roundtrip JSONB.
6. **Application layer** : providers + form controller (debounced) + results provider.
7. **Presentation layer** : `SimulatorPage` + form sections + KPI grid + chart + dialog save.
8. **Routes** : ajout `/simulator` + `/simulator/:id` dans `app_router.dart`.
9. **Dashboard link** : carte raccourci vers simulator (optionnel — confirmation product-owner).
10. **Tests** unit + widget via `qa-tester`.
11. **Review** : `code-reviewer` (clean code, naming, DRY) + `security-auditor` (RLS, JSONB validation, disclaimer fiscal).
12. **Deploy staging** → smoke test E2E (créer / éditer / supprimer / cross-user).
13. **State-keeper** : update `SCHEMA.md`, `ROUTES.md`, `FEATURES.md`.

## Open questions to surface to product-owner

1. **Disclaimer fiscal** : texte exact à afficher ? Bandeau permanent ou modal au premier accès ?
2. **Régimes fiscaux MVP** : on coupe à `micro_foncier` + `reel` + `micro_bic` ? Ou inclure LMNP simple ?
3. **Lien `properties` réelles** : MVP = scénarios standalone uniquement (pas de `property_id` FK) ?
4. **Limite nb scénarios** : quota par landlord ? (ex: 50 max pour éviter abus)
5. **Export PDF** du scénario (synthèse imprimable) : in-scope ou phase 2 ?
6. **Comparaison multi-scénarios** : side-by-side 2 scénarios ? In-scope ou phase 2 ?
