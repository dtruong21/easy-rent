# Routes — dashboard

> Source d'état — dashboard (accueil). Maintenu par state-keeper. Dernière sync : 2026-07-30.

## Accueil (shell branche 0, FEAT-027, fullyAuth, transition standard)

| Chemin | Page | Type | Guard | Notes |
|---|---|---|---|---|
| `/dashboard` | DashboardPage | read | fullyAuthenticated | KPI cards (loyers encaissés, retards, charges) + CTA navigate vers `/properties`, `/leases`, `/simulator` (autres branches/hors-shell) |

## Provider

- `chartPeriodProvider` (FEAT-027) : StateProvider<int>, SharedPreferences, défaut `12` (période graphe dashboard : 6/12/24 mois).

**FEATs** : FEAT-027 (dashboard, 1 route).
