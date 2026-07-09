# Routes — dashboard

> Source d'état — dashboard (accueil). Maintenu par state-keeper.

## Accueil (shell branche 0, FEAT-027, fullyAuth, transition standard)

| Chemin | Page | Type | Notes |
|---|---|---|---|
| `/dashboard` | DashboardPage | read | KPI cards (loyers encaissés, retards, charges) + CTA (Simulateur, Charges) ; drill-down KPI → `/leases?filter=late` |

## Provider

- `chartPeriodProvider` (FEAT-027) : StateProvider<int>, SharedPreferences, défaut `12` (période graphe dashboard : 6/12/24 mois).

**FEATs** : FEAT-027 (dashboard, 1 route).
