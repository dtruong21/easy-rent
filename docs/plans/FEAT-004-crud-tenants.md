# Plan — [FEAT-004] CRUD locataires

> Statut : **plan technique** (aucun code écrit). À valider par `product-owner` avant implémentation.
> **Plan de référence** : [`FEAT-003-crud-properties.md`](FEAT-003-crud-properties.md) — la quasi-totalité du pattern y est documentée. Ce plan ne décrit que les **différences** et les **décisions nouvelles**.

## Summary

CRUD UI complet sur la table `tenants` créée en FEAT-002. **Architecture strictement calquée sur FEAT-003** (même découpage, mêmes conventions, mêmes patterns Riverpod / go_router / freezed / json_serializable / RPC soft-delete). Trois différences fonctionnelles seulement : (1) modèle Tenant sans enum (4 champs scalaires), (2) email obligatoire avec validation format (réutilise `email_validator.dart`), (3) tri liste sur `last_name ASC` au lieu de `created_at DESC`. Aucune migration : `tenants`, ses RLS, son trigger `tr_01_prevent_protected_columns_change_tenants` et la RPC `soft_delete_tenant(p_id)` existent depuis FEAT-002. Effort estimé : **1,5 jour** (M) — gain par rapport à FEAT-003 grâce à la réutilisation des helpers `postgrest_error_mapper`, `email_validator`, et du dialog d'archivage.

## 1. Architecture

**Identique à FEAT-003.** Voir sections « Flutter changes » et « Décisions de design » du plan FEAT-003 pour :
- Découpage `data/domain/application/presentation` (cf. Q1, Q2, Q4 de FEAT-003).
- Pattern repository (interface + impl Supabase) cf. FEAT-003 §Flutter changes.
- Pattern providers (Repository, ListNotifier, DetailFamily, FormController autoDispose) cf. FEAT-003 §Providers Riverpod.
- Pattern route d'édition séparée `/...:id/edit` cf. FEAT-003 Q1.
- Pattern formulaire create/edit partagé `Tenant? initial` cf. FEAT-003 Q2.
- Pattern archivage via RPC + dialog avec avertissement bail actif cf. FEAT-003 Q3 & Q8.
- Pattern gestion d'erreur (`mapPostgrestError` + SnackBar + state union) cf. FEAT-003 Q9.
- Pattern pagination (limit 200) cf. FEAT-003 Q7.

**Nouvelle arborescence** :

```
lib/features/tenants/
├── data/
│   └── tenant_repository.dart          # interface + SupabaseTenantRepository
├── domain/
│   ├── tenant.dart                     # @freezed Tenant + @JsonSerializable
│   ├── tenant.freezed.dart             # généré
│   ├── tenant.g.dart                   # généré
│   ├── tenant_form_state.dart          # @freezed union idle/submitting/success/error
│   └── tenant_form_state.freezed.dart  # généré
├── application/
│   ├── tenants_list_provider.dart      # AsyncNotifier<List<Tenant>>
│   ├── tenant_detail_provider.dart     # family AsyncNotifier<Tenant>
│   └── tenant_form_controller.dart     # StateNotifier<TenantFormState>
└── presentation/
    ├── tenants_list_page.dart
    ├── tenant_detail_page.dart
    ├── tenant_form_page.dart
    └── widgets/
        ├── tenant_card.dart
        └── tenant_form.dart
        # PAS de archive_confirm_dialog.dart local — voir Q2 ci-dessous (mutualisation)
```

## 2. Modèle Dart `Tenant`

**Pas d'enum** (différence majeure vs `Property.type`). Quatre champs scalaires + timestamps + soft-delete.

```dart
@freezed
class Tenant with _$Tenant {
  const factory Tenant({
    required String id,
    required String landlordId,
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Tenant;

  factory Tenant.fromJson(Map<String, dynamic> json) => _$TenantFromJson(json);
}
```

- `@JsonSerializable(fieldRename: FieldRename.snake)` mappe `first_name → firstName`, etc.
- `deletedAt` exposé dans le modèle (utile pour les tests RLS-passthrough) mais filtré automatiquement par RLS côté serveur.
- Pas de `TenantDraft` séparé — la signature du `create(...)` du repo prend les champs explicitement (idem FEAT-003).

## 3. Repository

Mêmes contrats que `PropertyRepository` (cf. fichier `lib/features/properties/data/property_repository.dart`). Différences :

| Méthode | Différence vs FEAT-003 |
|---|---|
| `list()` | `.order('last_name', ascending: true).order('first_name', ascending: true).limit(200)` — tri alpha sur nom puis prénom pour stabilité quand deux locataires ont le même nom. |
| `getById(id)` | Identique (lance `TenantNotFoundException` si 0 ligne). |
| `create({firstName, lastName, email, phone})` | Payload Supabase = ces 4 champs (`first_name`, `last_name`, `email`, `phone`). Ne pas envoyer `landlord_id`. Ne pas envoyer `created_at/updated_at/deleted_at`. |
| `update(Tenant tenant)` | Payload = `first_name`, `last_name`, `email`, `phone` uniquement. |
| `countActiveLeases(tenantId)` | Identique à FEAT-003 mais filtre sur `tenant_id` au lieu de `property_id`. |
| `archive(id)` | `Db.rpc('soft_delete_tenant', params: {'p_id': id})`. |

**Export** : `export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;` (réutilisation, pas de duplication).

## 4. Providers

Renommage 1:1 des providers FEAT-003 :

| FEAT-003 | FEAT-004 |
|---|---|
| `propertyRepositoryProvider` | `tenantRepositoryProvider` |
| `propertiesListProvider` | `tenantsListProvider` |
| `propertyDetailProvider(id)` | `tenantDetailProvider(id)` |
| `propertyFormControllerProvider` | `tenantFormControllerProvider` (`autoDispose`) |

Comportement identique — invalidation après create/update/archive, family auto-cache sur les détails, etc.

## 5. Écrans

| Écran | Différences vs FEAT-003 |
|---|---|
| `TenantsListPage` | Tri `last_name ASC`. État vide « Aucun locataire enregistré » + FAB « Ajouter un locataire ». Pas de barre de recherche en V1 (cf. Q1). |
| `TenantDetailPage` | Affiche : nom complet (cf. Q5), email cliquable (`mailto:`), téléphone cliquable (`tel:` si présent). Section « Baux liés » → cf. Q6. Boutons « Modifier » (push `/tenants/:id/edit`) et « Archiver » (ouvre le dialog mutualisé). |
| `TenantFormPage` | Reçoit `Tenant? initial`. 4 `TextFormField` : Prénom, Nom, Email (`keyboardType: emailAddress`), Téléphone (`keyboardType: phone`). Validation à la perte de focus + à la soumission. |
| `widgets/tenant_card.dart` | Affiche nom (format Q5) + email en sous-titre + chevron. |
| `widgets/tenant_form.dart` | Form widget extrait — testable isolément. |

## 6. Validation

| Champ | Règle | Helper |
|---|---|---|
| `first_name` | `trim().isNotEmpty` | `tenant_form_validators.dart#validateFirstName` |
| `last_name` | `trim().isNotEmpty` | `tenant_form_validators.dart#validateLastName` |
| `email` | requis + `EmailValidator.isValid` | `tenant_form_validators.dart#validateEmail` (wrapper qui combine les deux) |
| `phone` | optionnel, string libre acceptée par le SQL (pas de regex en V1) | `tenant_form_validators.dart#validatePhone` (retourne toujours `null` en V1, mais le hook existe pour Q3) |

**Recommandation Q4** : créer un fichier dédié `lib/features/tenants/domain/tenant_form_validators.dart` (ou `lib/core/utils/tenant_form_validators.dart` pour cohérence avec `property_form_validators.dart` — préférence : `core/utils/`). **Ne pas** extraire en `text_validators.dart` partagé pour le moment — règle des trois (extraire au 3e usage, pas au 2e). `validateRequired` apparaîtrait dans `property_form_validators` + `tenant_form_validators` + un futur 3e ⇒ on extraira à ce moment-là.

## 7. Routes GoRouter

```dart
GoRoute(path: '/tenants', builder: (_, __) => const TenantsListPage()),
GoRoute(path: '/tenants/new', builder: (_, __) => const TenantFormPage(initial: null)),
GoRoute(
  path: '/tenants/:id',
  builder: (_, state) => TenantDetailPage(id: state.pathParameters['id']!),
),
GoRoute(
  path: '/tenants/:id/edit',
  builder: (_, state) => TenantFormPage.edit(id: state.pathParameters['id']!),
),
```

Aucune modif du `redirect` global — les routes héritent automatiquement de la garde authentifiée (cf. ROUTES.md).

## 8. Dashboard

Le `ListTile` « Mes locataires » est déjà présent en mode désactivé dans `dashboard_page.dart` (lignes 49-55). Travail :

1. Retirer `enabled: false`.
2. Ajouter `onTap: () => context.go('/tenants')`.
3. Ajouter `key: const Key('tile_tenants')` (cohérent avec `tile_properties`).
4. Mettre à jour le subtitle de « Disponible prochainement » → « Gérer votre annuaire de locataires ».

## 9. Tests à écrire

Granularité identique à FEAT-003.

### Unit (`test/unit/`)
- `tenant_test.dart` — sérialisation Tenant ↔ JSON (round-trip, phone null, dates ISO, deletedAt null).
- `tenant_form_validators_test.dart` — firstName/lastName vides, espaces uniquement, valeurs valides ; email invalide, vide, format OK ; phone (toujours null en V1).
- `tenant_repository_test.dart` — mocks `Db`, vérifie le payload create/update (pas de landlord_id, pas de timestamps), order par last_name, appel RPC `soft_delete_tenant`, levée de `TenantNotFoundException`.

### Widget (`test/widget/`)
- `tenants_list_page_test.dart` — état vide (texte + bouton), liste avec 3 items triés alpha, AsyncValue loading/error.
- `tenant_form_page_test.dart` — mode create (champs vides, erreurs inline sur soumission incomplète, soumission valide appelle le controller) + mode edit (champs pré-remplis).
- `tenant_detail_page_test.dart` — affichage des champs, bouton « Modifier » navigue vers `/tenants/:id/edit`, bouton « Archiver » ouvre le dialog (variante avec/sans bail actif).

### RLS
**Aucun nouveau test SQL.** `supabase/tests/rls_tenants.sql` est déjà livré par FEAT-002. Vérifier seulement lors du QA manuel qu'un user B ne voit pas les locataires de A.

### QA manuel
1. Avec un user A : créer 3 locataires (Dupont Jean, Martin Sophie, Durand Paul). Vérifier tri alpha sur `last_name`.
2. Tester chaque validation : email invalide → erreur inline ; prénom/nom vides → erreur inline.
3. Modifier un locataire, vérifier que `updated_at` change.
4. Archiver un locataire **sans bail** → disparaît, toast confirmation.
5. Insérer manuellement un `leases.status='active'` sur un locataire, tenter de l'archiver → message renforcé apparaît, archivage reste possible.
6. Avec user B connecté : `/tenants/<id-de-A>` → page « Locataire introuvable ».
7. Deep-link `/tenants/:id` après refresh navigateur → état restauré.

## 10. Risques & questions critiques

### Risques

| Risque | Probabilité | Mitigation |
|---|---|---|
| Stale state après archive/edit | Moyenne | `ref.invalidate(tenantsListProvider)` + `ref.invalidate(tenantDetailProvider(id))` après chaque action (pattern FEAT-003). |
| RLS renvoie 0 ligne (deep-link cross-user) | Certain (UX) | `TenantNotFoundException` ⇒ page « Locataire introuvable ». |
| Email déjà utilisé par un autre locataire du même landlord | Faible — aucune contrainte UNIQUE serveur en V1 | Pas de garde-fou client en V1. À documenter comme dette (post-MVP : éventuellement UNIQUE partiel). |
| Téléphone string libre → format incohérent | Moyenne | Acceptée en V1 (cf. Q3). Le champ apparaît tel quel dans les futures quittances → mention dans CHANGELOG. |
| Locataire archivé encore lié à un bail actif | Moyenne | Warning UX (dialog renforcé) — on N'INTERDIT PAS l'archivage (story le précise explicitement). Le bail reste actif côté DB. |
| Section « Baux liés » impossible avant FEAT-005 | Certain | Voir Q6 — placeholder lisible. |

### Questions critiques — recommandations

**Q1 — Recherche / filtre V1**
- Story : « optionnel V1 ».
- **Recommandation : reporter en P1.** Avec un tri alpha sur `last_name` et une cible 1-50 locataires/landlord, un Ctrl+F navigateur suffit. Ajouter un champ search ajoute : un `TextEditingController`, un `Provider` filter state, un debounce, des tests widget. Coût ~2h. Bénéfice marginal en V1. Si le PO insiste : version la plus simple = champ texte au-dessus de la liste, filtrage **côté client** sur la `List<Tenant>` déjà en mémoire (`firstName + lastName` lowercased contains query). Pas d'appel Supabase supplémentaire. 30-45 min dans ce cas.

**Q2 — Mutualisation `ArchiveConfirmDialog`**
- Le dialog actuel (`lib/features/properties/presentation/widgets/archive_confirm_dialog.dart`) hard-code « ce bien » dans les textes.
- **Recommandation : extraire dans `lib/core/widgets/archive_confirm_dialog.dart`** avec une signature paramétrée :
  ```dart
  ArchiveConfirmDialog({
    required String title,             // ex: "Archiver ce locataire ?"
    required String entityLabel,       // ex: "Jean Dupont"
    required String standardMessage,   // ex: "Voulez-vous archiver \"%s\" ?..."
    required String activeLeaseMessage,// ex: "Ce locataire a un bail actif..."
    required bool hasActiveLease,
    required VoidCallback onConfirm,
  })
  ```
- Garde le widget aussi simple qu'aujourd'hui ; la propriété est de pouvoir le réutiliser pour `Lease` en FEAT-005 et au-delà. La règle des trois ne s'applique pas vraiment ici : le widget est déjà conçu paramétré (seuls les strings hardcodées posent problème), et l'extraire **maintenant** évite une triple maintenance dans 2 semaines. Coût : 20 min. **Tâche à inclure dans FEAT-004.**

**Q3 — Validation téléphone**
- **Recommandation : V1 = string libre acceptée.** Story ne précise pas de format. SQL accepte n'importe quoi. Une regex FR (`^0[1-9](\s?\d{2}){4}$`) bloquerait les +33, les espaces non standard, les locataires étrangers. Validation = friction non justifiée en V1. **Documenter** dans le code que `validatePhone` retourne toujours `null` mais existe pour faciliter une évolution future (P1 : `phone_validator` package ou regex internationale).

**Q4 — Mutualisation des validateurs texte**
- **Recommandation : NE PAS extraire `text_validators.dart` maintenant.** Aujourd'hui on a 2 endroits qui valident « non vide » : `property_form_validators` (name/address) et `tenant_form_validators` (firstName/lastName). Règle des trois : on extrait au 3e usage. Le faire au 2e crée une abstraction prématurée qui peut mal vieillir (par exemple si une feature future veut une longueur min). Garder les validateurs spécifiques par feature, copier-coller assumé (4 lignes chacun).

**Q5 — Format d'affichage du nom**
- **Recommandation : `${firstName} ${lastName}` (français standard).** Plus convivial dans un produit B2C/B2B-light. Le style administratif `DUPONT Jean` est réservé aux documents légaux (quittance PDF FEAT-007 — où on appliquera ce format **uniquement dans le PDF**). Dans la liste, sur la fiche et dans le dialog, on reste sur le format prénom-nom naturel. Ajouter un getter `Tenant.displayName` qui renvoie `'$firstName $lastName'` (et plus tard un `Tenant.legalName` qui renvoie `'${lastName.toUpperCase()} $firstName'` pour le PDF).

**Q6 — Section « baux liés » sur la fiche**
- Story le demande, mais le CRUD baux n'arrive qu'en FEAT-005.
- **Recommandation : query directe `leases` + affichage minimal en V1.** La table existe, la RLS aussi, l'index `idx_public_leases_tenant_id` est là. La query est triviale (`SELECT id, status, start_date, end_date, property_id FROM leases WHERE tenant_id = ? AND deleted_at IS NULL ORDER BY start_date DESC`). On affiche dans une `Card` : statut (badge coloré), période, et un texte « Voir le bail » désactivé pour le moment (sera cliquable en FEAT-005). En l'absence de bail : « Aucun bail enregistré pour ce locataire ». Coût ~1h. Bénéfice : on respecte la story, on a un test E2E réel du compteur `countActiveLeases` pour l'archivage, on ne porte pas de placeholder embarrassant. **Pas de nouveau provider Riverpod dédié** : on expose une méthode `TenantRepository.listLeasesForTenant(tenantId)` qui retourne un `List<Map<String, dynamic>>` simple (pas besoin du modèle `Lease` typé, créé en FEAT-005). À refactorer en FEAT-005 pour utiliser le vrai modèle `Lease`.

## 11. Step-by-step execution order

1. **`supabase-dev`** — N/A (aucune migration ; éventuellement seed dev pour QA).
2. **`flutter-dev`** :
   1. Extraire `archive_confirm_dialog.dart` dans `lib/core/widgets/` (paramétrer les strings) + mettre à jour l'import dans FEAT-003 (`property_detail_page.dart`).
   2. `domain/` : `tenant.dart`, `tenant_form_state.dart` → `dart run build_runner build`.
   3. `core/utils/tenant_form_validators.dart`.
   4. `data/tenant_repository.dart` (interface + impl + exception + provider + méthode `listLeasesForTenant` cf. Q6).
   5. `application/` : 3 providers.
   6. `presentation/` : list page, form page, detail page (avec section baux), widgets.
   7. `core/router/app_router.dart` : ajout des 4 routes.
   8. `dashboard_page.dart` : activer le ListTile « Mes locataires ».
3. **`qa-tester`** — tests Dart + QA manuel.
4. **`code-reviewer`** — vérifie conformité (taille widgets, naming, pas de duplication évitable, doc des décisions).
5. **`security-auditor`** — vérifie qu'aucun INSERT/UPDATE n'envoie `landlord_id` / `created_at` / `updated_at` / `deleted_at`, que `archive()` passe par la RPC, que la validation email côté client n'est pas la seule barrière (CHECK SQL backup).
6. **`state-keeper`** — met à jour `docs/state/ROUTES.md` et `FEATURES.md`.

## 12. Estimation détaillée

| Étape | Effort |
|---|---|
| Extraction `ArchiveConfirmDialog` partagé | 20 min |
| Modèle + freezed + json + build_runner | 30 min |
| Validators + tests unit | 30 min |
| Repository + tests unit | 1h |
| Providers | 30 min |
| TenantsListPage + widget card | 1h |
| TenantFormPage + widget form + validation | 2h |
| TenantDetailPage + section baux (Q6) | 1h30 |
| Routes + dashboard activation | 15 min |
| Tests widget | 2h |
| QA manuel + corrections | 1h |
| **Total** | **~10h (1,5 jour)** |
