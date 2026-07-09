# Routes — leases

> Source d'état — leases (baux, chargeMode, charge_regularization). Maintenu par state-keeper.

## Baux (shell branche 3, FEAT-005, fullyAuth, transition standard)

| Chemin | Page | Type | Params / notes deep-link |
|---|---|---|---|
| `/leases` | LeasesListPage | read | drill-down `?filter=active\|renewable\|late` |
| `/leases/new` | LeaseFormPage | write | créer |
| `/leases/:id` | LeaseDetailPage | read | `id`=UUID ; `?action=regularize` (query) auto-ouvre dialog régularisation (FEAT-030, pas de subroute) |
| `/leases/:id/edit` | LeaseEditPage | write | `id`=UUID ; FEAT-036 : `chargesAmountCents` + `nonRecoverableChargesCents` |

**FEATs** : FEAT-005 (baux, 4 routes). Sous-routes paiements/quittances (`/leases/:id/payments…`, `/leases/:id/receipts`) → shard **payments-receipts**.
