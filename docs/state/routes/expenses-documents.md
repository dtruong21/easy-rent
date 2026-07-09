# Routes — expenses-documents

> Source d'état — expenses-documents (dépenses, documents). Maintenu par state-keeper.

## Dépenses par bien (shell branche 1 Biens, FEAT-041a, fullyAuth, transition standard)

| Chemin | Page | Type | Params / notes deep-link |
|---|---|---|---|
| `/properties/:id/expenses` | PropertyExpensesPage | read | listage dépenses bien ; onglet accessible depuis PropertyDetailPage |
| `/properties/:id/expenses/new` | ExpenseFormPage | write | créer ; `?leaseId=xxx` (via `state.extra`) pré-remplit depuis fiche bail |
| `/properties/:id/expenses/:eid/edit` | ExpenseEditPage | write | `id`=property UUID, `eid`=expense UUID |

Flux : Dashboard → drill-down property → onglet dépenses → `/expenses` → `new` ou `:eid/edit`.

**FEATs** : FEAT-041a (dépenses, 3 routes), FEAT-041b (documents v2 — intégré `createDocument`, pas de route dédiée).
