# Plan v1 — FEAT-017 + FEAT-018 Rentabilité & Simulateur

## Verdict global

**Ambitieux, livrable en 2 sprints solo SI on réduit drastiquement le scope FEAT-018 v1 et on tranche 4 décisions architecturales avant codage.** Les trois lentilles adversariales convergent sur "concerns" : (1) **scope-realism** alerte que FEAT-018 tel que designé pèse 35-45h (5-6j solo), au-dessus du seuil 5j/feature ; (2) **domain-expert FR** signale 3 imprécisions métier (charges récup vs non récup pas séparées, frais notaire neuf/ancien non distingués, cash-flow non labellé "avant impôt") qui exposent à des décisions utilisateur sur chiffres faussés ; (3) **integration-risk** trouve une incohérence majeure entre stories PO ("table `loan_scenarios` séparée") et schéma architect ("colonnes `loan_*` inline sur `properties`"), un naming divergent des charges, un `ScenariosDrawer` alors que le projet n'a aucun Drawer, et 11 fichiers de tests à refactorer. Pas bloquant, mais **lancer flutter-dev en l'état = 1 cycle de rework garanti**.

---

## FEAT-017 — Rentabilité portfolio existant

### User stories (top 3 MVP)

1. **US-017-1 — Saisie données financières d'acquisition** : 6 champs sur `PropertyForm` section "Financement" (ExpansionTile additive) — prix achat, date achat, frais notaire, taxe foncière annuelle, PNO annuelle, charges copro non récupérables annuelles. Tous optionnels. Persistance en cents.
2. **US-017-3 — KPIs rentabilité sur `PropertyDetailPage`** : section "Rentabilité" affichant rendement brut, rendement net, cash-flow mensuel, avec code couleur (rouge <5%, orange 5-7%, vert >7%), tooltips formules, et états gracieux "Données manquantes" / "Rendement net non calculable (charges manquantes)".
3. **US-017-4 — Vue agrégée Dashboard** : nouvelle section "Rentabilité portfolio" (distincte de la `KpiGrid` opérationnelle existante) avec 3 KPI cards — rendement brut moyen pondéré par prix d'acquisition, rendement net moyen, cash-flow mensuel total — + badge benchmark FR contextualisé.

US-017-2 (scénario prêt) et US-017-5 (règles d'exclusion) sont consolidées dans l'implémentation des 3 stories ci-dessus.

### Champs `properties` à ajouter (migration FEAT-017)

| Colonne | Type | Notes |
|---|---|---|
| `purchase_price_cents` | bigint NULL | CHECK > 0 AND < 100_000_000_000 |
| `purchase_date` | date NULL | |
| `notary_fees_cents` | bigint NULL | CHECK >= 0 |
| `is_new_property` | boolean DEFAULT false | Toggle ancien/neuf (impact frais notaire défaut) |
| `property_tax_annual_cents` | bigint NULL | Net de TEOM récupérable (documenter) |
| `insurance_pno_annual_cents` | bigint NULL | |
| `condo_fees_non_recoverable_cents` | bigint NULL | **Non récupérables uniquement** (gros travaux, syndic, ALUR) |
| `loan_principal_cents` | bigint NULL | Inline, pas de table séparée v1 |
| `loan_rate_basis_points` | int NULL | CHECK BETWEEN 0 AND 3000 |
| `loan_insurance_basis_points` | int NULL | CHECK BETWEEN 0 AND 200 |
| `loan_duration_months` | smallint NULL | CHECK BETWEEN 12 AND 360 |
| `loan_start_date` | date NULL | |
| `monthly_payment_cents` | bigint NULL | Surcharge manuelle prioritaire, sinon calc à la volée |

→ **Décision tranchée : prêt inline sur `properties`**, pas de table `loan_scenarios` séparée pour v1 (cf. décisions ouvertes #1).

### Compute engine

**Module pur Dart** : `lib/core/finance/profitability.dart` + `lib/core/finance/profitability_snapshot.dart` (freezed).

API livrée par FEAT-017 (consommée par FEAT-018) :
- `computeLoanMonthlyPaymentCents(principal, rateBps, durationMonths, insuranceBps)` — formule `P*i/(1-(1+i)^-n)` avec branchement taux=0, assurance calculée sur capital initial
- `computeAmortizationSchedule(...)` → `List<AmortizationRow>` (ajouté v1 car partagé avec FEAT-018)
- `computeYieldGrossPercent(annualRentHcCents, totalAcquisitionCents)`
- `computeYieldNetPercent(annualRentHcCents, annualChargesCents, totalAcquisitionCents)`
- `computeMonthlyCashflowCents(...)` — labellé "avant impôt"
- `computeProfitabilitySnapshot(property, lease, payments12m)` → `ProfitabilitySnapshot(isComplete, missingFields, gross, net, cashflow)`

100% testable en isolation, aucune dépendance Flutter/Supabase.

### UI changes

- **`PropertyForm`** : nouvelle `ExpansionTile` "Financement & acquisition" (pattern existant FEAT-014, additive)
- **`PropertyDetailPage`** : nouvelle section "Rentabilité" via widget `PropertyProfitabilityCard` (pattern `EntityCard`)
- **`DashboardPage`** : nouvelle section "Rentabilité portfolio" (2e section sous `KpiGrid` opérationnelle existante, **pas insérée dans la grille pour éviter saturation 7 KPI**)
- **Mention légale** "Estimation indicative avant impôt — ne tient pas compte du régime fiscal ni des prélèvements sociaux 17,2%" sous chaque widget rentabilité

### Effort estimé

**21-25h (3-3.5j solo)** incluant :
- Migration + CHECK constraints + RLS : 2h
- Compute engine + tests unit : 5h (engine 3h + amortization +1h + tests 1h)
- `PropertyForm` section Financement + controller refacto + 11 fakes tests à updater : 6h
- `PropertyProfitabilityCard` + tooltips + états dégradés : 3h
- Dashboard `PortfolioYieldKpi` (×3) + badge benchmark FR : 3h
- Loyer annuel glissant 12 mois sur `payments` (jointures, edge cases) : 2h
- Disclaimer + extension export RGPD + tests RLS cross-user : 2h

### Risques identifiés (par lentilles)

- **scope-realism** : limite haute mais réaliste *si* open questions tranchées avant codage. 7 open questions architect sans réponse = risque rework.
- **domain-expert FR** : (a) charges copro doivent être **non récupérables uniquement** (sinon rendement net faussé), (b) frais notaire 7,5% ancien vs 2,5% neuf — toggle `is_new_property` requis, (c) cash-flow et rendement net doivent être labellés "avant impôt", (d) benchmark "5-7% norme FR" trompeur sans nuance géographique (Paris 2-4% vs villes secondaires 7%+), (e) TEOM (part ordures de la taxe foncière) techniquement récupérable — à documenter.
- **integration-risk** : (a) incohérence stories vs architect sur `loan_scenarios` → tranché inline, (b) naming `insurance_pno` vs `insurance_annual` + `condo_fees` vs `hoa` → tranché stories (FR-friendly), (c) 11 fakes `PropertyRepository.create()` à updater — opportunité d'extraire `MockPropertyRepository` dans `test/helpers/`, (d) vérifier `StatusPillTone.amber` existe pour badge "Dans la norme", sinon l'ajouter.

---

## FEAT-018 — Simulateur futur

### User stories (top 3 MVP — scope RÉDUIT vs design original)

1. **US-018-2 — Saisie formulaire scénario (simplifié)** : 12 champs au lieu de 17 (retirer : taux assurance emprunteur séparé → constante 0,30%, vacancy_rate → fixé 5% défaut, appreciation_rate → fixé 1,5% défaut, projection_years → fixé 20 ans, works_initial conservé pour cohérence prix acquisition avec FEAT-017).
2. **US-018-3 — Affichage 8 indicateurs** (au lieu de 13) : mensualité totale, loyer net annuel (vacance déduite), cash-flow mensuel (labellé **avant impôt**), rendement brut, rendement net, total intérêts versés, coût total crédit, valeur estimée à terme. **Pas de TRI, pas de régime fiscal, pas de chart fl_chart, pas de comparaison multi-scénarios** en v1.
4. **US-018-4 — Sauvegarde et chargement** : CRUD basique scénarios (create, list, load, delete) + RLS strict.

**Out of scope v1** (reporté P2) : TRI/IRR, régimes fiscaux (micro-foncier/micro-BIC/réel), `ResultsCashflowChart` fl_chart, comparaison 2-3 scénarios side-by-side, lien vers properties existantes.

### Table `investment_scenarios`

```sql
CREATE TABLE investment_scenarios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid NOT NULL REFERENCES landlords(id) ON DELETE CASCADE DEFAULT auth.uid(),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  -- Colonnes TYPÉES (recommandation security audit, pas JSONB)
  purchase_price_cents bigint NOT NULL CHECK (purchase_price_cents > 0),
  notary_fees_cents bigint NOT NULL CHECK (notary_fees_cents >= 0),
  works_initial_cents bigint NOT NULL DEFAULT 0,
  is_new_property boolean NOT NULL DEFAULT false,
  down_payment_cents bigint NOT NULL CHECK (down_payment_cents >= 0),
  loan_principal_cents bigint NOT NULL CHECK (loan_principal_cents >= 0),
  loan_rate_bps int NOT NULL CHECK (loan_rate_bps BETWEEN 0 AND 3000),
  loan_duration_months smallint NOT NULL CHECK (loan_duration_months BETWEEN 12 AND 360),
  monthly_rent_hc_cents bigint NOT NULL CHECK (monthly_rent_hc_cents > 0),
  property_tax_annual_cents bigint NOT NULL DEFAULT 0,
  insurance_pno_annual_cents bigint NOT NULL DEFAULT 0,
  condo_fees_non_recoverable_cents bigint NOT NULL DEFAULT 0,
  notes text NULL CHECK (length(notes) <= 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz NULL
);

CREATE POLICY "owner_only" ON investment_scenarios FOR ALL TO authenticated
  USING (landlord_id = auth.uid()) WITH CHECK (landlord_id = auth.uid());
```

→ **Colonnes typées** (pas JSONB) sur recommandation security audit, défense contre injection + validation DB native + queries SQL fine-grained possibles.

### Page `/simulator`

- Route `/simulator` (GoRouter, auth required) → `SimulatorPage`
- Route `/simulator/:id` → `SimulatorEditPage`
- **Pas de Drawer** (`ScenariosDrawer` design rejeté — aucun Drawer dans l'app aujourd'hui). Remplacé par :
  - Liste scénarios sauvegardés en haut de `/simulator` (ListView horizontal de `EntityCard`)
  - Accès depuis Dashboard via nouveau `Shortcut "Simulateur"` dans `ShortcutsRow`
- Calcul live debounced 200-300ms via Provider.autoDispose
- Disclaimer permanent en haut des résultats : *"Estimation indicative basée sur les données saisies. Ne constitue pas un conseil en investissement. Consultez un professionnel."*

### Dépendance FEAT-017

**CRITIQUE** : FEAT-018 consomme `lib/core/finance/` livré par FEAT-017. Le contrat API est aligné v1 (rendement brut/net, cash-flow, mensualité, amortissement). **TRI, régimes fiscaux et projection multi-années sont reportés P2** — donc FEAT-017 v1 n'a pas besoin de les livrer. Pas de fork mini-engine.

### Effort estimé

**18-22h (3j solo)** après réduction scope :
- Migration `investment_scenarios` + RLS + tests cross-user : 3h
- Routes + page `/simulator` + auth guard + Shortcut Dashboard : 2h
- `ScenarioForm` 12 champs en 4 sections + validators : 5h
- `ResultsKpiGrid` 8 indicateurs + codes couleur : 3h
- CRUD scénarios (`SaveScenarioDialog`, liste, load, delete) : 3h
- Disclaimer + extension RGPD : 1h
- Tests widget + integration RLS : 3h

### Risques identifiés

- **scope-realism** : design original 35-45h (5-6j) **bloquant**. Scope réduit ici à 18-22h. Toute extension v1 (TRI, fiscal, chart, comparaison) ramène au-dessus du seuil.
- **domain-expert FR** : (a) disclaimer fiscal obligatoire (responsabilité civile si chiffres mal interprétés), (b) frais notaire défaut doit dépendre de `is_new_property` (2,5% neuf vs 7,5% ancien), (c) cash-flow doit explicitement dire "avant impôt", (d) assurance emprunteur sur capital initial (constante) — choix documenté.
- **integration-risk** : (a) `fl_chart` retiré du scope → pas de risque pubspec v1, (b) `ScenariosDrawer` remplacé par pattern existant, (c) colonnes typées au lieu de JSONB → cohérent avec `leases`/`payments`.

---

## Sécurité / RGPD

**Risques critiques (sign-off conditionnel security-auditor)** :

1. **Données financières = données patrimoniales sensibles** (art. 32 RGPD minimisation + sécurité). Mitigation : update `consent_version` FEAT-016 avec mention "données financières pour calculs rentabilité, jamais partagées", extension export RGPD (nouvelles colonnes `properties` + `investment_scenarios`), cascade ON DELETE depuis `landlords`, scrubber Sentry sur valeurs financières.

2. **RLS `investment_scenarios`** : pattern identique `leases` — `landlord_id = auth.uid()` USING + WITH CHECK, DEFAULT `auth.uid()`, trigger `tr_00_set_landlord_id`, **tests cross-user explicites** dans `tests/integration/rls_investment_scenarios_test.dart`.

3. **CHECK constraints DB obligatoires** : taux 0-3000 bps, durée 12-360 mois, prix > 0, frais >= 0. Côté Dart : validators Riverpod en miroir (defense-in-depth).

4. **Disclaimer simulateur — risque légal civil** : bannière permanente sur `/simulator` + sous chaque KPI rentabilité dans `PropertyProfitabilityCard`. Logger acceptation dans `consent_version`. Constantes fiscales (si introduites P2) dans `tax_constants.dart` avec source BOFiP datée.

5. **Pas de logging Sentry/Crashlytics** sur `principal_cents`, `purchase_price_cents`, `monthly_income_cents` → scrubber client + server, vérifier config GA4 si présente.

**Sign-off conditionnel OK si** : RLS cross-user testée + CHECK constraints + disclaimer + extension export RGPD + scrubber logs. **Sinon bloquant**.

---

## Ordre d'exécution recommandé

**Sprint 1 — FEAT-017 (3-3.5j)** d'abord, **strictement avant FEAT-018** :
- Le module `lib/core/finance/` est livré par FEAT-017 et consommé par FEAT-018. Sans lui, FEAT-018 doit forker un mini-engine local = dette technique immédiate.
- Le pattern formulaire `PropertyForm` section "Financement" sert de modèle à `ScenarioForm` (DRY validators, mapping cents).
- Refacto fakes tests (`MockPropertyRepository` mixin) bénéficie à tout le projet — meilleur fait tôt.
- Migration `properties` (12 colonnes additives) plus simple à valider avant de toucher à une nouvelle table.

**Sprint 2 — FEAT-018 v1 minimaliste (3j)** après merge FEAT-017 :
- Consomme directement `lib/core/finance/`
- Pas de blocage architectural
- Scope réduit valide à 1 sprint solo

**Sprint 3+ (futur)** : FEAT-018 v2 (TRI, régimes fiscaux, chart fl_chart, comparaison multi-scénarios) — feature dédiée, pas un add-on.

---

## Décisions ouvertes à valider AVANT codage

1. **Modélisation prêt : inline `properties` ou table `loan_scenarios` séparée ?**
   *Recommandation : inline sur `properties` pour v1.* Plus simple, moins de RLS à tester, scope minimal. Reporter `loan_scenarios` (historisation + multi-scénarios par bien) en P2 si besoin produit prouvé.

2. **Charges copropriété : montant total OU non récupérables uniquement ?**
   *Recommandation : non récupérables uniquement* (champ `condo_fees_non_recoverable_cents`). Sinon le rendement net est mécaniquement faussé pour un bailleur qui saisit ses appels de charges complets. Aligner UI label : "Charges copropriété **non récupérables** (gros travaux, syndic, ALUR)".

3. **KPIs rentabilité sur Dashboard : insérer dans `KpiGrid` existante OU section séparée ?**
   *Recommandation : section "Rentabilité portfolio" séparée*, sous la `KpiGrid` opérationnelle existante. Évite la saturation 7 KPI et sépare visuellement opérationnel (loyers/retards) de stratégique (rendement).

4. **Bien vacant (aucun bail actif) : fallback dernier bail terminé OU "rentabilité non calculable" ?**
   *Recommandation : "Bien vacant — rentabilité non calculable"* + CTA "Créer un bail". Évite complexité fallback + cohérent avec philosophie "données fiables uniquement" de US-017-5.

5. **`fl_chart` pour FEAT-018 v1 ?**
   *Recommandation : NON.* KPI cards uniquement v1. Chart de projection 20 ans = P2. Évite ajout dépendance majeure + 3h widget custom.

---

## Estimation totale v1

| Module | Effort solo | Risque |
|---|---|---|
| FEAT-017 | **21-25h (3-3.5j)** | medium (open questions, refacto fakes tests) |
| FEAT-018 v1 réduit | **18-22h (3j)** | medium (dépendance FEAT-017, disclaimer légal) |
| **Total v1** | **~40-47h (6-7j soit ~1,5 sprint solo)** | medium |

**Livrable en 2 sprints consécutifs**, pas 1. Le scope FEAT-018 original (35-45h) aurait fait dérailler le sprint 2 — la réduction (TRI, régimes fiscaux, chart, comparaison reportés P2) est **non négociable** pour rester dans le budget. Si le produit-owner refuse cette réduction, prévoir 3 sprints (FEAT-017 / FEAT-018 v1 minimal / FEAT-018 v2 enrichi).
