# Routes — dashboard

> Source d'état — dashboard (accueil). Maintenu par state-keeper. Dernière sync : 2026-09-15.

## Accueil (shell branche 0, FEAT-027, fullyAuth, transition standard)

| Chemin | Page | Type | Guard | Notes |
|---|---|---|---|---|
| `/dashboard` | DashboardPage | read | fullyAuthenticated | KPI cards (loyers encaissés, retards, charges) + graphique cash-flow mensuel + section rentabilité portfolio + activité récente + checklist d'onboarding (FEAT-058) ; CTA navigate vers `/properties`, `/leases`, `/simulator` (autres branches/hors-shell) |

## Checklist d'onboarding progressif (FEAT-058)

Affichée en haut du dashboard tant qu'aucune quittance n'a été générée (`hasReceipt == false`) ET que l'utilisateur ne l'a pas explicitement passée (`onboardingDismissedProvider == false`). Bloc entièrement local, **100 % client** (lecture des données, zéro backend).

**5 étapes séquentielles**, dérivées des données Firestore :
1. **Créer un bien** : cochée si `properties.length > 0` (collection non-vide)
2. **Ajouter un locataire** : cochée si `tenants.length > 0`
3. **Créer un bail** : cochée si `leases.length > 0`
4. **Enregistrer un paiement** : cochée si le bailleur a ≥ 1 paiement (`hasPayment` — requête `payments` scopée `landlordId`, **tous baux confondus**, pas au seul `firstLeaseId`) — **désactivée sans bail** (UI grisée, non-interactive ; le `firstLeaseId` ne sert qu'à router le lien d'action)
5. **Générer une quittance** : cochée si le bailleur a ≥ 1 quittance (`hasReceipt` — requête `receipts` scopée `landlordId`, tous baux confondus) — **désactivée sans bail** — ***fin de l'onboarding lorsque franchie***

Chaque étape affiche un statut visuel (case à cocher) et un lien d'action contextuelle (`/properties`, `/leases`, `/leases/<firstLeaseId>/payments/new`, `/receipts`). Étapes 4–5 sont automatiquement grisées si pas de premier bail.

**Dismiss local** : bouton « Passer » persiste l'état `onboardingDismissedProvider` (SharedPreferences clé `onboarding_dismissed:bool`), masquant le bloc jusqu'à l'actualisation ou un changement d'état utilisateur.

**Fonte de données** : `DashboardRepository.fetchOnboardingProgress()` → `OnboardingProgress {hasProperty, hasTenant, hasLease, hasPayment, hasReceipt, firstLeaseId?, completedCount, isComplete}`. Snapshot complété au chargement du dashboard via `DashboardSnapshot.onboarding` (AsyncValue<OnboardingProgress?>). Pas d'appel additionnel.

## Providers & État

- `dashboardProvider` (AsyncNotifierProvider) : charge le snapshot complet (4 KPI + activité, 30 items + onboarding) via parallélisation records Dart 3. Court-circuité si déjà complété (premier login après quittance générée). Expose `refresh()` (RefreshIndicator).
- `onboardingDismissedProvider` (StateProvider<bool>, SharedPreferences) : state utilisateur du dismiss local (FEAT-058).
- `monthlyCashflowProvider` (independant du dashboard) : charge le graphique « Cash-flow mensuel » sur la période sélectionnée (6/12/24 mois). Ne recharge pas les KPI si la période change.
- `chartPeriodProvider` (FEAT-027) : StateProvider<int>, SharedPreferences, défaut `12` (période graphe dashboard : 6/12/24 mois).
- `chartFormatProvider` (FEAT-027) : StateProvider<ChartFormat> — format graphique (brut, cumulé, taux).

## Modèles

| Modèle | Notes |
|---|---|
| `DashboardSnapshot` | 3 KPI (LoyersMoisKpi, RetardsKpi, DocsPendingKpi) + List<ActivityItem> + OnboardingProgress? |
| `OnboardingProgress` | `{hasProperty, hasTenant, hasLease, hasPayment, hasReceipt, firstLeaseId?, completedCount, isComplete}` — dérivé des données, jamais muté ; getter `isComplete` → checklist entièrement cochée |
| `MonthlyCashflow` | year, month, collectedRentCents, nonRecoverableExpenseCents, loanPaymentCents, hasData → getter `netCents` (loyers - dépenses - mensualité) |
| `MonthlyCollectedRent` | Helper pour agrégation loyers mensuels (brique du cashflow) |
| `ActivityItem` | Activité récente (paiements, baux, documents, etc.) |

**FEATs** : FEAT-027 (dashboard, 1 route + KPI + graphique), FEAT-058 (onboarding progressif jusqu'à 1re quittance).
