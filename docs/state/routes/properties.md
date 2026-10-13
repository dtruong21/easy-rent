# Routes — properties

> Source d'état — properties (biens + locataires). Maintenu par state-keeper. Dernière sync : 2026-09-05.

## Biens (shell branche 1, FEAT-003, fullyAuth, transition standard)

| Chemin | Page | Type | Params / notes |
|---|---|---|---|
| `/properties` | PropertiesListPage | read | grid/table toggleable (FEAT-012) ; cartes affichent la couleur d'identité du bien (FEAT-044d) |
| `/properties/new` | PropertyFormPage | write | créer |
| `/properties/:id` | PropertyDetailPage | read | `id`=UUID ; détail + liens baux + onglet dépenses (routes → expenses-documents) ; affiche la couleur du bien (FEAT-044d) |
| `/properties/:id/edit` | PropertyEditPage | write | éditer |

## Locataires (shell branche 2, FEAT-004, fullyAuth, transition standard)

| Chemin | Page | Type | Params / notes |
|---|---|---|---|
| `/tenants` | TenantsListPage | read | listage |
| `/tenants/new` | TenantFormPage | write | `?picker=1` → pop `tenantId` au lieu de go `/tenants` |
| `/tenants/:id` | TenantDetailPage | read | `id`=UUID |
| `/tenants/:id/edit` | TenantEditPage | write | éditer |

**FEATs** : FEAT-003 (biens, 4 routes), FEAT-004 (locataires, 4 routes). Note : routes dépenses `/properties/:id/expenses…` → shard **expenses-documents**.
