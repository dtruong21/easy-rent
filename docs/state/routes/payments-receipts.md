# Routes — payments-receipts

> Source d'état — payments-receipts (paiements, quittances). Maintenu par state-keeper.

## Sous-routes de bail (shell branche 3, fullyAuth, transition standard)

| Chemin | Page | Type | Params / notes |
|---|---|---|---|
| `/leases/:id/payments/new` | PaymentFormPage | write | FEAT-006 ; FEAT-029 : `notes` motif |
| `/leases/:id/payments/:pid/edit` | PaymentEditPage | write | `id`=lease UUID, `pid`=payment UUID |
| `/leases/:id/receipts` | LeaseReceiptsPage | read | FEAT-007 : generate + share + archive quittances |

**FEATs** : FEAT-006 (paiements, 2 routes), FEAT-007 (quittances, 1 route), FEAT-029 (charges — champ `payment.notes`).
