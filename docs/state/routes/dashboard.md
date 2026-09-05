# Routes — dashboard

> Source d'état — dashboard (accueil). Maintenu par state-keeper. Dernière sync : 2026-09-05.

## Accueil (shell branche 0, FEAT-027, fullyAuth, transition standard)

| Chemin | Page | Type | Guard | Notes |
|---|---|---|---|---|
| `/dashboard` | DashboardPage | read | fullyAuthenticated | KPI cards (loyers encaissés, retards, charges) + graphique cash-flow mensuel + section rentabilité portfolio + activité récente + onboarding si aucun bien/locataire/bail ; CTA navigate vers `/properties`, `/leases`, `/simulator` (autres branches/hors-shell) |

## Providers & État

- `dashboardProvider` (AsyncNotifierProvider) : charge le snapshot complet (4 KPI + activité, 30 items) via parallélisation records Dart 3. Court-circuité si onboarding. Expose `refresh()` (RefreshIndicator).
- `monthlyCashflowProvider` (independant du dashboard) : charge le graphique « Cash-flow mensuel » sur la période sélectionnée (6/12/24 mois). Ne recharge pas les KPI si la période change.
- `chartPeriodProvider` (FEAT-027) : StateProvider<int>, SharedPreferences, défaut `12` (période graphe dashboard : 6/12/24 mois).
- `chartFormatProvider` (FEAT-027) : StateProvider<ChartFormat> — format graphique (brut, cumulé, taux).

## Modèles

| Modèle | Notes |
|---|---|
| `DashboardSnapshot` | 4 KPI (LoyersMoisKpi, RetardsKpi, RenouvellementsKpi, DocsPendingKpi) + List<ActivityItem> + isOnboarding |
| `MonthlyCashflow` | year, month, collectedRentCents, nonRecoverableExpenseCents, loanPaymentCents, hasData → getter `netCents` (loyers - dépenses - mensualité) |
| `MonthlyCollectedRent` | Helper pour agrégation loyers mensuels (brique du cashflow) |
| `ActivityItem` | Activité récente (paiements, baux, documents, etc.) |

**FEATs** : FEAT-027 (dashboard, 1 route + KPI + graphique).
