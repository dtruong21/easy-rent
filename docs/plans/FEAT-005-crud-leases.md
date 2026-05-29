# Plan — [FEAT-005] CRUD baux

> Statut : **plan technique** (aucun code écrit). À valider par `product-owner` (voir §11 Open questions) avant implémentation.
> **Plans de référence** : [`FEAT-003-crud-properties.md`](FEAT-003-crud-properties.md) et [`FEAT-004-crud-tenants.md`](FEAT-004-crud-tenants.md). Ce plan ne décrit **que les différences et les décisions nouvelles** par rapport au pattern CRUD déjà mergé deux fois.

## Summary

CRUD UI complet sur la table `leases` créée en FEAT-002. **Architecture strictement calquée sur FEAT-003 / FEAT-004** (même découpage `data/domain/application/presentation`, mêmes patterns Riverpod / go_router / freezed / json_serializable / RPC soft-delete). Quatre différences fonctionnelles majeures par rapport à FEAT-004 :
1. **Modèle pivot** : deux FK (`property_id` + `tenant_id`) avec affichage joint (nom du bien + nom du locataire) dans la liste.
2. **Montants en centimes** stockés en `integer` Postgres, convertis euros↔centimes uniquement côté client. Nouveau helper `money_format.dart` (intl `fr_FR`).
3. **Status workflow** : enum `LeaseStatus { active, terminated, archived }` (CHECK SQL existant), avec une opération métier dédiée « clôturer le bail » (status `active → terminated` + `end_date`), distincte de l'archivage soft-delete.
4. **Avertissement bail actif existant** : avant insert/update sur `status=active`, on vérifie qu'aucun autre bail actif n'existe pour le même `property_id`. Si oui → dialog de confirmation (override possible, cas copropriété).

Aucune migration : la table `leases`, ses RLS, son trigger `tr_00_assert_lease_ownership` cross-FK, et la RPC `soft_delete_lease(p_id)` existent depuis FEAT-002 et sont entièrement conformes à la story. Effort estimé : **2 jours** (M) — un peu plus que FEAT-004 (1.5j) à cause du formulaire à deux dropdowns, du flow de clôture, et de la jointure d'affichage.

## 1. Confirmation du schéma — aucune migration

La table `leases` (public + dev) couvre **100 %** de la story telle que rédigée. Vérification colonne par colonne :

| Story exige | Schéma actuel (cf. `docs/state/SCHEMA.md`) | OK ? |
|---|---|---|
| FK property | `property_id uuid NOT NULL FK properties(id) ON DELETE RESTRICT` | ✅ |
| FK tenant | `tenant_id uuid NOT NULL FK tenants(id) ON DELETE RESTRICT` | ✅ |
| FK landlord (RLS) | `landlord_id uuid NOT NULL FK landlords(id) ON DELETE RESTRICT` | ✅ |
| Loyer HC en centimes | `rent_amount_cents integer NOT NULL CHECK > 0` | ✅ |
| Charges en centimes | `charges_amount_cents integer NOT NULL DEFAULT 0 CHECK >= 0` | ✅ |
| start_date | `date NOT NULL` | ✅ |
| end_date optionnelle | `date NULL, CHECK end_date > start_date` | ✅ |
| Statut Actif / Terminé | `status text NOT NULL DEFAULT 'active' CHECK IN ('active','terminated','archived')` | ✅ |
| Soft-delete | `deleted_at + RPC soft_delete_lease(p_id)` | ✅ |
| RLS isolation | 3 policies `leases_select_own / insert_own / update_own` (public + dev) | ✅ |
| Cohérence FK cross-landlord | Trigger `tr_00_assert_lease_ownership` SECURITY DEFINER | ✅ |
| Index status actif | `idx_public_leases_status_active_partial` (WHERE status='active' AND deleted_at IS NULL) | ✅ |

**Conclusion** : **AUCUNE migration à écrire.** Si pendant l'implémentation un besoin émerge (ex : index pour la jointure liste), il sera tracé comme tâche séparée — mais a priori inutile à 1-50 baux/landlord.

Contraintes que le code Flutter DOIT respecter (rappel) :

| Colonne | Contrainte serveur | Conséquence côté Flutter |
|---|---|---|
| `landlord_id` | RLS WITH CHECK = auth.uid() + trigger ownership | **Ne pas l'envoyer** depuis le client. La RLS le fixe. |
| `property_id`, `tenant_id` | FK + trigger `assert_lease_ownership_consistency` valide que les deux appartiennent au landlord courant | Si le user pioche dans les dropdowns alimentés via RLS, ce trigger ne lèvera **jamais** d'erreur en pratique (filet de sécurité côté serveur). |
| `rent_amount_cents` | integer NOT NULL > 0 | Convertir euros (`double` ou `String`) → centimes (`int`) **avant** insert. |
| `charges_amount_cents` | integer NOT NULL >= 0 (default 0) | 0 accepté. Si le champ est vide côté UI → envoyer `0`, pas `null`. |
| `end_date` | date NULL, CHECK end_date > start_date | Côté client : if `endDate != null && !endDate.isAfter(startDate)` → erreur inline. |
| `status` | CHECK IN (3 valeurs) | Enum Dart fermé `LeaseStatus`. |
| `created_at`, `updated_at`, `deleted_at` | Gérés par triggers | **Jamais** inclure dans payloads INSERT/UPDATE. |

## 2. Backend (Edge Functions)

**N/A** — Aucune logique serveur custom. Tout passe par REST/PostgREST + la RPC `soft_delete_lease` existante.

## 3. Modèle Dart `Lease`

Quatre champs scalaires + deux FK + montants en centimes + dates + statut. Pas de `Tenant` ni de `Property` imbriqués dans le modèle principal (cf. §4.1 pour la jointure d'affichage).

```dart
@freezed
class Lease with _$Lease {
  const factory Lease({
    required String id,
    required String landlordId,
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    required LeaseStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Lease;

  factory Lease.fromJson(Map<String, dynamic> json) => _$LeaseFromJson(json);
}
```

- `@JsonSerializable(fieldRename: FieldRename.snake)` mappe `property_id → propertyId`, `rent_amount_cents → rentAmountCents`, etc.
- `startDate` / `endDate` sont des `DateTime` côté Dart mais sérialisés en string `YYYY-MM-DD` côté Postgres (`date`). Json conversion explicite via `@JsonKey(fromJson: _dateFromJson, toJson: _dateToJson)` car le décodage par défaut tenterait un ISO 8601 complet — sera handlé dans `lease.dart` (helpers privés).
- Getters utiles à ajouter sur le freezed (via `@Implements` ou extension) :
  - `int get totalAmountCents => rentAmountCents + chargesAmountCents;` (loyer CC) — **via extension** (pas dans freezed).
  - `bool get isActive => status == LeaseStatus.active && deletedAt == null;`
  - `bool get isClosed => status == LeaseStatus.terminated;`

### Enum `LeaseStatus`

```dart
enum LeaseStatus {
  active,
  terminated,
  archived;

  String get labelFr => switch (this) {
    LeaseStatus.active => 'Actif',
    LeaseStatus.terminated => 'Terminé',
    LeaseStatus.archived => 'Archivé',
  };

  String get sqlValue => name;

  static LeaseStatus fromSql(String value) =>
      LeaseStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => LeaseStatus.archived, // tolérance défensive
      );
}
```

> Note : la valeur `archived` n'est pas exposée à l'utilisateur via aucune action UI en FEAT-005. Elle est **réservée** au soft-delete (la RPC `soft_delete_lease` met `deleted_at` à `now()` mais ne touche **pas** `status` — donc en pratique `archived` ne sera jamais écrit par le code Flutter en V1, sauf si un futur use-case le demande). On la garde dans l'enum pour matcher le CHECK SQL et résister à des données existantes.

### Modèle composé pour la liste : `LeaseListItem`

La liste affiche **nom du bien + nom du locataire** en plus des champs `Lease`. Deux options :
- A : faire une jointure Postgrest `select('*, properties(name), tenants(first_name, last_name)')` et créer un modèle `LeaseListItem` distinct (id, propertyName, tenantDisplayName, rentCC, status, startDate).
- B : ne pas joindre, faire 3 queries séparées (`list leases`, `list properties`, `list tenants`) puis joiner côté Dart.

**Recommandation : A (jointure Postgrest)**, sur les arguments suivants :
- Postgrest gère nativement les jointures FK (`tenants(first_name, last_name)` retourne un objet imbriqué). Code Dart ~3 lignes.
- À 1-50 baux, le payload reste sous 20 KB.
- Évite 2 round-trips réseau + une logique de join côté client.
- RLS s'applique aux tables jointes — un user ne peut pas voir le bien/locataire d'un autre user via cette syntaxe.

```dart
final rows = await Db.from('leases')
  .select('*, property:properties(id, name), tenant:tenants(id, first_name, last_name)')
  .order('status', ascending: true)     // active en premier
  .order('start_date', ascending: false) // plus récent en premier
  .limit(200);
```

Modèle `LeaseListItem` (pas freezed — POJO simple, sérialisation manuelle depuis le JSON joint) :

```dart
class LeaseListItem {
  const LeaseListItem({
    required this.lease,
    required this.propertyName,
    required this.tenantDisplayName,
  });

  final Lease lease;
  final String propertyName;
  final String tenantDisplayName;

  factory LeaseListItem.fromJson(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>?;
    final tenant = json['tenant'] as Map<String, dynamic>?;
    return LeaseListItem(
      lease: Lease.fromJson(json),
      propertyName: property?['name'] as String? ?? '(bien archivé)',
      tenantDisplayName: tenant != null
          ? '${tenant['first_name']} ${tenant['last_name']}'
          : '(locataire archivé)',
    );
  }
}
```

> Edge case géré : si le bien ou le locataire a été soft-deleted entre-temps, la jointure renverra `null` côté Postgrest (car RLS filtre `deleted_at IS NULL` sur les tables jointes). On affiche un placeholder lisible plutôt que de crasher.

### Conversion euros ↔ centimes

**Stratégie : helpers purs dans `lib/core/utils/money_format.dart`.**

```dart
class MoneyFormat {
  /// Convertit un montant en euros (string ou double) vers centimes.
  /// Tolère ',' et '.'. Retourne null si invalide.
  static int? eurosToCents(String input) {
    final cleaned = input.trim().replaceAll(',', '.').replaceAll(' ', '');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed < 0) return null;
    return (parsed * 100).round(); // round() pour éviter 8499 sur 84.99
  }

  /// Formate des centimes en string FR avec € : "1 234,56 €".
  static String centsToDisplay(int cents) {
    final euros = cents / 100;
    final formatter = NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2);
    return formatter.format(euros);
  }

  /// Formate des centimes en input FR sans € : "1234,56" (pour pré-remplir le form en édition).
  static String centsToInput(int cents) {
    final euros = cents / 100;
    return euros.toStringAsFixed(2).replaceAll('.', ',');
  }
}
```

> `intl` est déjà dans `pubspec.yaml` (^0.19.0) — aucune dépendance à ajouter. Tests unitaires obligatoires pour les cas limites : `0.01`, `9999999.99`, virgule, point, espace insécable, négatif, `"abc"`, vide.

## 4. Repository

Interface `LeaseRepository` + impl `SupabaseLeaseRepository` — mêmes contrats que `PropertyRepository` / `TenantRepository` avec quelques additions :

```dart
abstract interface class LeaseRepository {
  /// Liste tous les baux du landlord courant — joint avec property + tenant pour l'affichage.
  Future<List<LeaseListItem>> listForDisplay();

  Future<Lease> getById(String id);

  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    // status n'est PAS exposé : toujours 'active' à la création (default SQL).
  });

  Future<Lease> update(Lease lease);

  /// Clôture un bail actif : status → 'terminated', end_date = effectiveEndDate, updated_at = now().
  /// Lève [LeaseAlreadyClosedException] si le bail n'est pas 'active'.
  Future<Lease> close(String id, {required DateTime effectiveEndDate});

  /// Retourne true si un autre bail (≠ excludeLeaseId) est actif sur ce propertyId.
  /// Utilisé pour afficher l'avertissement avant create/update.
  Future<bool> hasOtherActiveLeaseOnProperty(String propertyId, {String? excludeLeaseId});

  /// Archive (soft-delete) via RPC `soft_delete_lease`.
  Future<void> archive(String id);
}
```

Détails d'implémentation Supabase :

| Méthode | Implémentation |
|---|---|
| `listForDisplay()` | `Db.from('leases').select('*, property:properties(id, name), tenant:tenants(id, first_name, last_name)').order('status').order('start_date', ascending: false).limit(200)` puis `.map(LeaseListItem.fromJson)`. |
| `getById(id)` | `select()` (sans join — la fiche détail va recharger property et tenant séparément via les providers existants `propertyDetailProvider` / `tenantDetailProvider`). Lève `LeaseNotFoundException` si 0 ligne. |
| `create(...)` | Payload : `property_id`, `tenant_id`, `rent_amount_cents`, `charges_amount_cents`, `start_date` (ISO `YYYY-MM-DD`), `end_date` (nullable). **Pas** de `landlord_id`, **pas** de `status`, **pas** de timestamps. |
| `update(Lease)` | Mêmes champs que create + tous éditables (cf. story : "tous les champs sont modifiables"). On peut potentiellement éditer `status` aussi mais cf. §5 Q2 : on **réserve** le changement de status à `close()` pour clarté UX. |
| `close(id, effectiveEndDate)` | `update({'status': 'terminated', 'end_date': effectiveEndDate}).eq('id', id).eq('status', 'active').select()` — l'`eq('status', 'active')` garantit l'atomicité (race-condition safe). Si 0 row → lève `LeaseAlreadyClosedException`. |
| `hasOtherActiveLeaseOnProperty(propertyId, excludeLeaseId)` | `select('id').eq('property_id', propertyId).eq('status', 'active').filter('deleted_at', 'is', null).limit(2)` (limit 2 pour distinguer "1 = self" de "≥2"). Puis filtre côté Dart sur excludeLeaseId. Renvoie `true` si au moins un id ≠ excludeLeaseId reste. |
| `archive(id)` | `Db.rpc('soft_delete_lease', params: {'p_id': id})`. |

**Export error mapper** : `export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;` — réutilisation pure.

## 5. Providers Riverpod

Renommage 1:1 du pattern FEAT-004 :

| Provider | Type | Rôle |
|---|---|---|
| `leaseRepositoryProvider` | `Provider<LeaseRepository>` | Expose `SupabaseLeaseRepository`. |
| `leasesListProvider` | `AsyncNotifierProvider<LeasesListNotifier, List<LeaseListItem>>` | Liste joint property+tenant. |
| `leaseDetailProvider(id)` | `AsyncNotifierProviderFamily<LeaseDetailNotifier, Lease, String>` | Fiche bail. |
| `leaseFormControllerProvider` | `StateNotifierProvider.autoDispose<LeaseFormController, LeaseFormState>` | Contrôle le formulaire. |

`LeaseFormState` (union freezed) — identique à `TenantFormState` :
- `idle`
- `submitting`
- `success(Lease lease)`
- `error(String message)`

Le controller a une méthode dédiée pour la clôture, **séparée** de `submit()`, car l'UX et l'invalidation sont différentes :

```dart
class LeaseFormController extends StateNotifier<LeaseFormState> {
  Future<void> submit({Lease? initial, /* ... champs métier ... */}) async { /* idem tenant */ }

  /// Clôture (status active → terminated). Distinct de submit() : pas de re-validation
  /// des champs métier, juste status + end_date.
  Future<void> close({required String leaseId, required DateTime effectiveEndDate}) async {
    state = const LeaseFormState.submitting();
    try {
      final repo = _ref.read(leaseRepositoryProvider);
      final result = await repo.close(leaseId, effectiveEndDate: effectiveEndDate);
      _ref.invalidate(leasesListProvider);
      _ref.invalidate(leaseDetailProvider(leaseId));
      state = LeaseFormState.success(lease: result);
    } on LeaseAlreadyClosedException catch (_, st) {
      state = const LeaseFormState.error(message: 'Ce bail est déjà clôturé.');
    } on PostgrestException catch (e, st) {
      state = LeaseFormState.error(message: mapPostgrestError(e));
    } catch (e, st) {
      state = const LeaseFormState.error(message: 'Une erreur est survenue. Veuillez réessayer.');
    }
  }
}
```

**Providers auxiliaires (Dropdown)** : pour alimenter les deux dropdowns du formulaire, on **réutilise** `propertiesListProvider` (FEAT-003) et `tenantsListProvider` (FEAT-004) — déjà filtrés par RLS, déjà cachés. Pas besoin de provider dédié.

## 6. Écrans

```
lib/features/leases/
├── data/
│   └── lease_repository.dart           # interface + SupabaseLeaseRepository + exceptions
├── domain/
│   ├── lease.dart                      # @freezed Lease + extension getters
│   ├── lease.freezed.dart              # généré
│   ├── lease.g.dart                    # généré
│   ├── lease_status.dart               # enum + labelFr + sqlValue + fromSql
│   ├── lease_list_item.dart            # POJO + fromJson (Postgrest join)
│   ├── lease_form_state.dart           # @freezed union
│   └── lease_form_state.freezed.dart   # généré
├── application/
│   ├── leases_list_provider.dart       # AsyncNotifier<List<LeaseListItem>>
│   ├── lease_detail_provider.dart      # family AsyncNotifier<Lease>
│   └── lease_form_controller.dart      # StateNotifier<LeaseFormState> + close()
└── presentation/
    ├── leases_list_page.dart
    ├── lease_detail_page.dart
    ├── lease_form_page.dart            # CREATE + EDIT (initial: Lease?)
    └── widgets/
        ├── lease_card.dart             # item de liste
        ├── lease_form.dart             # form widget (extrait pour testabilité)
        ├── lease_status_badge.dart     # badge coloré (réutilise palette tenant_lease_summary)
        ├── active_lease_warning_dialog.dart # confirmation "ce bien a déjà un bail actif"
        └── close_lease_dialog.dart     # confirmation clôture avec date picker
```

| Écran | Comportement |
|---|---|
| `LeasesListPage` | Cards (mobile-first, pas de DataTable en V1 — cf. Q1). Chaque card : nom bien (gras), nom locataire, loyer CC formaté (`1 234,56 €`), badge statut, période. Tri : `status ASC` (active d'abord) puis `start_date DESC`. État vide « Aucun bail enregistré » + FAB « Créer un bail ». État d'erreur + retry. |
| `LeaseFormPage` | Reçoit `Lease? initial`. Champs : `DropdownButtonFormField<Property>` (depuis `propertiesListProvider`), `DropdownButtonFormField<Tenant>` (depuis `tenantsListProvider`), 2 `TextFormField` montants (suffixe `€`, keyboard `numberWithOptions(decimal: true)`), 2 date pickers (start obligatoire, end optionnelle avec checkbox « bail à durée indéterminée » pour expliciter le `null`). Validation à la soumission + perte de focus. À la soumission : si propertyId déjà dans un autre bail actif (`hasOtherActiveLeaseOnProperty`) → `ActiveLeaseWarningDialog`, override possible. |
| `LeaseDetailPage` | Lecture-only. Affiche : statut (badge), bien lié (lien `context.go('/properties/:id')`), locataire lié (lien `/tenants/:id`), loyer HC, charges, loyer CC, période. **Section paiements** : placeholder « Suivi des paiements disponible après FEAT-006 » (cf. Q5). Actions : « Modifier » (push `/leases/:id/edit`), « Clôturer » si `status==active` (ouvre `CloseLeaseDialog`), « Archiver » (ouvre `ArchiveConfirmDialog` mutualisé). |
| `LeaseFormPage.edit(id)` factory | Lit `leaseDetailProvider(id)` + passe `initial: lease` au form. Spinner pendant le load. |
| `widgets/lease_card.dart` | Card cliquable → push `/leases/:id`. |
| `widgets/lease_form.dart` | Form widget extrait — testable isolément avec dropdowns mockés. |
| `widgets/lease_status_badge.dart` | Réutilise le pattern de `_StatusBadge` dans `tenant_lease_summary.dart` (qu'on peut éventuellement promouvoir en widget partagé — cf. Q3). |
| `widgets/active_lease_warning_dialog.dart` | « Ce bien a déjà un bail actif. Voulez-vous quand même créer ce bail ? » + boutons Annuler / Continuer. |
| `widgets/close_lease_dialog.dart` | Titre « Clôturer ce bail ». Date picker pré-rempli à aujourd'hui (label : « Date de fin effective »). Boutons Annuler / Clôturer. Sur clôture → appelle `controller.close(...)`. |

## 7. Validation

Nouveau fichier `lib/core/utils/lease_form_validators.dart` (même convention que `tenant_form_validators.dart` et `property_form_validators.dart`).

| Champ | Règle | Helper |
|---|---|---|
| `propertyId` | requis (un Property sélectionné) | `validateProperty(Property?) → String?` |
| `tenantId` | requis (un Tenant sélectionné) | `validateTenant(Tenant?) → String?` |
| `rentAmount` (euros, string saisi) | requis ; `MoneyFormat.eurosToCents` ≠ null ; > 0 | `validateRentAmount(String?) → String?` |
| `chargesAmount` (euros, string saisi) | requis ; `MoneyFormat.eurosToCents` ≠ null ; ≥ 0 (0 accepté) | `validateChargesAmount(String?) → String?` |
| `startDate` | requis | `validateStartDate(DateTime?) → String?` |
| `endDate` | optionnel ; si présent → `endDate.isAfter(startDate)` (strict) | `validateEndDate(DateTime? end, DateTime? start) → String?` |

> Messages d'erreur en français, alignés sur l'AC de la story :
> - "Le loyer doit être un montant positif"
> - "Les charges ne peuvent pas être négatives"
> - "La date de fin doit être postérieure à la date de début"
> - "Veuillez sélectionner un bien"
> - "Veuillez sélectionner un locataire"

## 8. Routes GoRouter

```dart
GoRoute(path: '/leases',         builder: (_, __) => const LeasesListPage()),
GoRoute(path: '/leases/new',     builder: (_, __) => const LeaseFormPage()),
GoRoute(path: '/leases/:id',     builder: (_, s) => LeaseDetailPage(id: s.pathParameters['id']!)),
GoRoute(path: '/leases/:id/edit',builder: (_, s) => LeaseEditPage(id: s.pathParameters['id']!)),
```

Aucune modif du `redirect` global — les routes héritent automatiquement de la garde authentifiée.

## 9. Dashboard

Le `ListTile` « Mes baux » est déjà présent en mode désactivé dans `dashboard_page.dart` (lignes 58-64, `enabled: false`). Travail :

1. Retirer `enabled: false`.
2. Ajouter `onTap: () => context.go('/leases')`.
3. Ajouter `key: const Key('tile_leases')` (cohérent avec `tile_properties`, `tile_tenants`).
4. Mettre à jour le subtitle de « Disponible prochainement » → « Gérer vos contrats de location ».

## 10. Tests à écrire (~80 tests cible)

Granularité identique à FEAT-004 (80+ tests). Liste ci-dessous, par fichier.

### Unit (`test/unit/`)

| Fichier | Cas testés (~) |
|---|---|
| `lease_test.dart` | round-trip JSON, `endDate` null, dates ISO YYYY-MM-DD, deletedAt null. Extension getters : `totalAmountCents`, `isActive`, `isClosed`. |
| `lease_status_test.dart` | `fromSql` connus + fallback `archived`, `labelFr` les 3 cas, `sqlValue`. |
| `lease_list_item_test.dart` | `fromJson` avec property+tenant complets, placeholder si property null, placeholder si tenant null. |
| `money_format_test.dart` | `eurosToCents` : virgule, point, espace, négatif, vide, "abc", 0, 9999999.99. `centsToDisplay` : 0, 100, 12345 (= 123,45 €), arrondi. `centsToInput` : 0, 12345. **Locale fr_FR forcée pour reproductibilité.** |
| `lease_form_validators_test.dart` | Tous les champs cités au §7 : valides, invalides, edge cases. |
| `lease_repository_test.dart` | Mocks `Db` : vérifie payload create (pas de landlord_id, pas de status, pas de timestamps), update (mêmes champs), close (filter `status='active'`), `hasOtherActiveLeaseOnProperty` (gestion excludeLeaseId), levée de `LeaseNotFoundException` + `LeaseAlreadyClosedException`, appel RPC `soft_delete_lease`. |

### Widget (`test/widget/`)

| Fichier | Cas testés (~) |
|---|---|
| `leases_list_page_test.dart` | État vide (texte + FAB), liste avec 3 items triés `active → terminated`, AsyncValue loading/error, navigation card → `/leases/:id`. |
| `lease_form_page_test.dart` | Mode create : tous champs vides, erreurs inline sur soumission incomplète, soumission valide appelle le controller. Mode edit : champs pré-remplis (montants formatés `1234,56`), dropdowns sélectionnés. Validation `end_date > start_date`. Toggle « durée indéterminée » désactive le date picker end_date. |
| `lease_detail_page_test.dart` | Affichage tous champs, lien property → `/properties/:id`, lien tenant → `/tenants/:id`. Bouton « Clôturer » visible si `active`, caché si `terminated`. Bouton « Archiver » ouvre `ArchiveConfirmDialog`. |
| `active_lease_warning_dialog_test.dart` | Affichage du message, boutons Annuler (ferme) / Continuer (appelle callback). |
| `close_lease_dialog_test.dart` | Date picker pré-rempli à aujourd'hui, boutons Annuler / Clôturer (appelle callback avec date sélectionnée). |
| `lease_card_test.dart` | Affichage nom bien, nom locataire, loyer formaté, badge statut. |
| `lease_status_badge_test.dart` | 3 variantes (active, terminated, archived) — couleurs + labels FR. |

### RLS (`supabase/tests/`)

**Aucun nouveau test SQL.** `supabase/tests/rls_leases.sql` est déjà livré par FEAT-002 (20+ tests). Vérifier seulement en QA manuel qu'un user B ne voit pas les baux du user A.

### QA manuel

1. Avec user A : créer 2 biens (B1, B2) et 2 locataires (L1, L2). Créer un bail B1 ↔ L1 (loyer 850€, charges 50€, début aujourd'hui, pas de fin). Vérifier badge « Actif ».
2. Tenter de créer un second bail B1 ↔ L2 → dialog d'avertissement. Annuler → pas de création. Re-tenter → confirmer → bail créé.
3. Modifier le loyer du 1er bail (850 → 900 €). Vérifier sur la fiche que la valeur est mise à jour.
4. Tester chaque validation : loyer négatif, fin < début, dropdowns vides → erreurs inline.
5. Cliquer « Clôturer » sur un bail actif → date picker pré-rempli aujourd'hui → confirmer → status passe à « Terminé », end_date renseignée. Vérifier qu'il reste visible dans la liste.
6. Re-tenter « Clôturer » sur un bail déjà clôturé → bouton non affiché (cf. AC).
7. Archiver un bail terminé → disparaît de la liste, deleted_at posé. Vérifier qu'il ne réapparaît pas après refresh.
8. Avec user B : tenter `/leases/<id-de-A>` → page « Bail introuvable » (RLS).
9. Refresh navigateur sur `/leases/:id` → état restauré, fiche affichée.
10. Format FR : vérifier `1 234,56 €` (espace insécable, virgule décimale) sur la liste et la fiche.
11. Cliquer sur le nom du bien dans la fiche → navigation vers `/properties/:id`. Idem locataire → `/tenants/:id`.

## 11. Open questions for orchestrator

Chaque question a une recommandation par défaut (`[Q]`). L'orchestrator peut soit valider, soit demander un override avant codage.

**Q1 — Liste : Cards vs DataTable**
- Recommandation : **Cards** (mobile-first, cohérent avec FEAT-003/004). Une DataTable web améliore le scan rapide à 50+ baux mais coûte plus en widget (responsive, sort, etc.). À 1-20 baux/landlord cible MVP, les cards suffisent.
- **Défaut si silence** : Cards.

**Q2 — Édition du `status` libre vs réservée à la clôture**
- La story dit « tous les champs sont modifiables » côté édition. Mais permettre de changer librement `active → terminated` dans le form génère deux flows pour la même action (form OU dialog dédié).
- Recommandation : **réserver le changement de status au flow « Clôturer le bail »**. Le formulaire d'édition ne montre **pas** de dropdown status. Justification : (1) la clôture exige une date effective explicite (impossible à exprimer en édition libre), (2) UX plus claire, (3) la story décrit "clôturer" comme un flow distinct. Risque : un utilisateur qui veut un changement de status hors clôture (cas inconnu) doit nous le signaler. Acceptable.
- **Défaut si silence** : status non éditable dans le form ; clôture via dialog dédié uniquement.

**Q3 — `LeaseStatusBadge` : nouveau widget partagé ou copy-paste depuis `tenant_lease_summary` ?**
- Le widget `_StatusBadge` existant dans `tenant_lease_summary.dart` est privé (`_`). On l'utilise déjà à 1 endroit. Si on l'extrait, on aura 2 usages.
- Recommandation : **extraire** dans `lib/core/widgets/lease_status_badge.dart` (ou `entity_status_badge.dart` si on veut le rendre générique pour un futur `PaymentStatus`). Mettre à jour `tenant_lease_summary.dart` pour le consommer. Coût : 30 min. Bénéfice : un seul endroit pour la palette de statuts, un seul fichier de tests widget pour le badge.
- **Défaut si silence** : extraire en `lib/core/widgets/lease_status_badge.dart`.

**Q4 — Affichage `end_date` dans la liste**
- La story mentionne « date de début » dans la liste mais pas la fin. Possibilités : (a) afficher juste `start_date`, (b) afficher `Du DD/MM/YYYY au DD/MM/YYYY` (ou « (CDI) » si null), (c) afficher uniquement si terminated.
- Recommandation : **option (b)** — toujours afficher la période, indique « (CDI) » si null. C'est ce que fait déjà `tenant_lease_summary.dart` (cohérence visuelle).
- **Défaut si silence** : période complète avec « (CDI) » si end_date null.

**Q5 — Section « Liste des paiements » sur la fiche bail**
- AC dit « la liste des paiements associés (vide si FEAT-005/006 pas encore implémentés) ». Mais la table `payments` n'existe pas encore — elle viendra avec FEAT-006 ou FEAT-008.
- Recommandation : **placeholder texte uniquement**, pas de query DB. Texte : « Suivi des paiements disponible après FEAT-006 ». À transformer en provider + liste en FEAT-006. Coût : 5 lignes.
- **Défaut si silence** : placeholder texte uniquement.

**Q6 — Wording exact du dialog « bail actif existant »**
- Texte proposé : « Ce bien a déjà un bail actif. Voulez-vous quand même créer ce bail ? Cas usuels : copropriété, erreur de saisie, transition entre locataires. »
- Recommandation : adopter ce wording. Validation finale du wording = `product-owner`.
- **Défaut si silence** : wording ci-dessus.

**Q7 — Reverse navigation property/tenant → bail actif**
- L'AC demande implicitement (« lien vers `/properties/:id` et `/tenants/:id` ») mais l'inverse n'est pas spécifié. Aujourd'hui :
  - `tenant_detail_page.dart` affiche déjà `TenantLeaseSummary` (query directe, cf. FEAT-004). Il faudra **rendre cliquable** la mention « Voir le bail (disponible après FEAT-005) » pour qu'elle pointe vers `/leases/:id`. Coût : 10 lignes (passer `onTap` au widget).
  - `property_detail_page.dart` n'affiche pas de section baux aujourd'hui (cf. FEAT-003 plan). À ajouter ? **Out of scope strict de la story FEAT-005**, mais utile pour la cohérence avec tenants.
- Recommandation : **scope FEAT-005 minimal** = (1) rendre cliquable le summary tenant (10 lignes, 30 min, fini une dette FEAT-004) ; (2) ne **PAS** ajouter de section baux sur la fiche property (créer une story FEAT-005b ou inclure dans FEAT-009 dashboard). À surfacer à l'orchestrator.
- **Défaut si silence** : on inclut (1) dans FEAT-005, on n'inclut pas (2).

**Q8 — Tri par défaut de la liste**
- AC ne précise pas. Recommandation : `status ASC` (active d'abord — pertinence métier) puis `start_date DESC` (plus récent en premier). Cohérent avec `tenant_lease_summary.dart`.
- **Défaut si silence** : `status ASC, start_date DESC`.

**Q9 — Couleur du badge `terminated` et `archived`**
- Story ne précise pas. Recommandation : reprendre la palette de `_StatusBadge` dans `tenant_lease_summary.dart` :
  - `active` → `colorScheme.primary` (bleu/violet selon le theme)
  - `terminated` → `colorScheme.outline` (gris)
  - `archived` → `colorScheme.outline` (gris) — mais ce statut ne devrait pas apparaître dans la liste en V1 (filtré par RLS via `deleted_at`).
- **Défaut si silence** : palette ci-dessus.

## 12. Risques

| Risque | Probabilité | Mitigation |
|---|---|---|
| Stale state après archive/edit/close | Moyenne | `ref.invalidate(leasesListProvider) + leaseDetailProvider(id)` après chaque action — pattern hérité de FEAT-004. |
| Jointure Postgrest renvoie `null` sur bien/locataire archivé | Faible (mais possible) | `LeaseListItem.fromJson` affiche placeholder lisible (« (bien archivé) »). Tests unitaires explicites. |
| Race condition sur clôture (deux tabs simultanés) | Faible | `update().eq('status', 'active')` côté SQL — atomique. Lève `LeaseAlreadyClosedException` si le bail n'est plus actif. |
| Arrondi flottant lors euros→centimes (`84.99 * 100 = 8498.999...`) | Certaine si on n'arrondit pas | `MoneyFormat.eurosToCents` fait `.round()` explicitement. Test unitaire dédié sur `0.10`, `0.20`, `99.99`, `84.99`. |
| Dropdown vide si user n'a aucun bien ou aucun locataire | Certaine pour un compte neuf | UI : afficher message « Vous devez d'abord créer un bien / un locataire » + bouton vers `/properties/new` ou `/tenants/new`. |
| Format date FR (DD/MM/YYYY) vs ISO Postgres (YYYY-MM-DD) | Moyenne | Helpers privés dans `lease.dart` (`_dateFromJson` / `_dateToJson`). Tests unitaires sur round-trip. |
| Trigger `assert_lease_ownership_consistency` lève une erreur si on essaye d'insérer une combinaison invalide (jamais via UI mais via dev tooling) | Faible | `mapPostgrestError` traduit ERRCODE 23514 en message FR clair. Test unitaire sur l'erreur. |
| Section paiements crée une attente UX non livrée | Moyenne | Wording explicite « disponible après FEAT-006 » + style désactivé. |

## 13. Step-by-step execution order

1. **`supabase-dev`** — N/A (aucune migration). Seed dev optionnel : `INSERT INTO dev.leases (...)` pour démarrer le QA manuel avant la création UI.
2. **`flutter-dev`** :
   1. `lib/core/utils/money_format.dart` + tests unitaires.
   2. `lib/core/widgets/lease_status_badge.dart` (cf. Q3) + tests + refactor `tenant_lease_summary.dart` pour l'utiliser.
   3. `domain/` : `lease_status.dart`, `lease.dart`, `lease_list_item.dart`, `lease_form_state.dart` → `dart run build_runner build`.
   4. `lib/core/utils/lease_form_validators.dart` + tests.
   5. `data/lease_repository.dart` (interface + impl + exceptions + provider) + tests unitaires repo (mocks `Db`).
   6. `application/` : 3 providers.
   7. `presentation/widgets/` : `lease_card.dart`, `lease_form.dart`, `active_lease_warning_dialog.dart`, `close_lease_dialog.dart` (+ tests widget).
   8. `presentation/` : `leases_list_page.dart`, `lease_form_page.dart`, `lease_detail_page.dart` (+ tests widget).
   9. `core/router/app_router.dart` : ajout des 4 routes.
   10. `dashboard_page.dart` : activer le ListTile « Mes baux ».
   11. `tenant_detail_page.dart` / `tenant_lease_summary.dart` : rendre cliquable le lien vers `/leases/:id` (cf. Q7).
3. **`qa-tester`** — exécute tous les tests Dart + le QA manuel ci-dessus.
4. **`code-reviewer`** — vérifie : taille widgets (≤ 300 LOC), conventions naming, pas de duplication évitable, doc des décisions, conversion euros↔centimes uniquement côté client (jamais double dans le payload).
5. **`security-auditor`** — vérifie : aucun INSERT/UPDATE n'envoie `landlord_id` / `status` / timestamps / `deleted_at` ; `archive()` passe par RPC ; `close()` est idempotent (filter `status='active'`) ; pas de leak cross-user via la jointure Postgrest (vérification manuelle d'un endpoint dev).
6. **`state-keeper`** — met à jour `docs/state/ROUTES.md` et `FEATURES.md` post-merge.

## 14. Estimation détaillée

| Étape | Effort |
|---|---|
| `money_format.dart` + tests (cas limites arrondi) | 1h |
| Extraction `LeaseStatusBadge` + refactor `tenant_lease_summary` | 30 min |
| Modèles freezed + json + enum + build_runner | 1h |
| Validators + tests unit | 30 min |
| Repository + exceptions + tests unit (mocks) | 1h30 |
| Providers (3) | 30 min |
| `LeasesListPage` + `LeaseCard` | 1h30 |
| `LeaseFormPage` + `LeaseForm` (2 dropdowns, montants, dates, toggle CDI) | 3h |
| `LeaseDetailPage` + section paiements placeholder | 1h |
| Dialogs : `ActiveLeaseWarning` + `CloseLease` (avec date picker) | 1h |
| Tests widget (7 fichiers) | 3h |
| Routes + dashboard + cliquable lien tenant→lease | 30 min |
| QA manuel + corrections | 1h30 |
| **Total** | **~16h (2 jours)** |
