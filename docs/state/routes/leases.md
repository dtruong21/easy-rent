# Routes — leases

> Source d'état — leases (baux, chargeMode, charge_regularization). Maintenu par state-keeper.

## Baux (shell branche 3, FEAT-005, fullyAuth, transition standard)

| Chemin | Page | Type | Params / notes deep-link |
|---|---|---|---|
| `/leases` | LeasesListPage | read | drill-down `?filter=active\|renewable\|late` |
| `/leases/new` | LeaseFormPage | write | créer |
| `/leases/:id` | LeaseDetailPage | read | `id`=UUID ; `?action=regularize` (query) auto-ouvre dialog régularisation (FEAT-030, pas de subroute) — **gate Pro appliqué aussi sur ce deep-link** (PR #120) |
| `/leases/:id/edit` | LeaseEditPage | write | `id`=UUID ; FEAT-036 : `chargesAmountCents` + `nonRecoverableChargesCents` |

## Régularisation des charges — double gate (PR #120)

Ordre de précédence **volontaire**, à ne pas inverser :

1. **Gate LÉGAL d'abord** : bail au forfait → message d'inapplicabilité (`Lease.canRegularizeCharges` = `effectiveChargeMode == provisions`, FEAT-042). Un compte free sur un bail au forfait voit le message légal, **pas** un upsell — il serait trompeur de vendre une fonction que la loi n'autorise pas sur ce bail.
2. **Gate PRO ensuite** : réservé au palier `paid`. Gate **client uniquement** (calcul + PDF 100 % côté client : restriction produit, pas frontière de sécurité — rien à protéger côté serveur).
3. **Fail-closed** pendant le chargement du tier (pas de flash du bouton). Clé l10n `chargeRegularizationProOnly` (FR + EN).

**FEATs** : FEAT-005 (baux, 4 routes), FEAT-042 (chargeMode), FEAT-044 (gate Pro). Sous-routes paiements/quittances (`/leases/:id/payments…`, `/leases/:id/receipts`) → shard **payments-receipts**.
