# Plan — [FEAT-003] CRUD biens immobiliers

> Statut : **plan technique** (aucun code écrit). À valider par `product-owner` (voir Questions critiques) avant implémentation.

## Summary

CRUD UI complet sur la table `properties` créée en FEAT-002. La structure reproduit fidèlement le pattern `lib/features/auth/` (data/domain/application/presentation), avec un `PropertyRepository` (interface + impl Supabase via `Db.from()`), un modèle `Property` en `freezed` + `json_serializable`, et trois écrans (liste / fiche / formulaire partagé création-édition). L'archivage passe **obligatoirement** par la RPC `soft_delete_property(p_id)` car le trigger `tr_01_prevent_protected_columns_change_*` bloque tout UPDATE direct sur `deleted_at`. La RLS de FEAT-002 prend en charge l'isolation cross-user (aucun travail côté Flutter pour ça). Aucune migration : le schéma existe déjà. Effort estimé : **2 jours** (M).

## Data model changes

**Aucune migration.** La table `properties` (public + dev), ses policies RLS (`properties_select_own`, `properties_insert_own`, `properties_update_own`), le trigger `prevent_protected_columns_change` et la RPC `soft_delete_property(p_id uuid)` ont été livrés en FEAT-002.

Rappel des contraintes que le code Flutter DOIT respecter :

| Colonne | Contrainte serveur | Conséquence côté Flutter |
|---|---|---|
| `name` | NOT NULL, length > 0 | Validation client `required`, `trim().isNotEmpty` |
| `address` | NOT NULL, length > 0 | Validation client `required`, `trim().isNotEmpty` |
| `type` | CHECK IN ('appartement','maison','studio','autre') | Enum Dart fermé, jamais de saisie libre |
| `surface_m2` | numeric(6,2), CHECK > 0 si non NULL | Validation client : optionnel, mais si présent → > 0, max 9999.99 |
| `landlord_id` | FK + RLS WITH CHECK `= auth.uid()` | **Ne pas l'envoyer** depuis le client — la RLS le rejette si ≠ uid. À setter dans le repo via `Supabase.instance.client.auth.currentUser!.id` |
| `created_at`, `updated_at`, `deleted_at` | Gérés par triggers | **Ne jamais** les inclure dans payloads INSERT/UPDATE |

## Backend (Edge Functions)

**N/A** — Aucune logique serveur custom requise. Tout passe par REST/PostgREST + la RPC existante.

## Flutter changes

### Arborescence de la feature

```
lib/features/properties/
├── data/
│   └── property_repository.dart       # interface + SupabasePropertyRepository
├── domain/
│   ├── property.dart                  # @freezed Property + @JsonSerializable
│   ├── property.freezed.dart          # généré
│   ├── property.g.dart                # généré
│   ├── property_type.dart             # enum + extension FR + mapping SQL
│   └── property_form_state.dart       # @freezed union idle/submitting/success/error
│   └── property_form_state.freezed.dart # généré
├── application/
│   ├── properties_list_provider.dart  # AsyncNotifier<List<Property>>
│   ├── property_detail_provider.dart  # family AsyncNotifier<Property> par id
│   └── property_form_controller.dart  # StateNotifier<PropertyFormState>
└── presentation/
    ├── properties_list_page.dart      # GET /properties
    ├── property_detail_page.dart      # GET /properties/:id
    ├── property_form_page.dart        # POST /properties/new + édition (voir Q1/Q2)
    └── widgets/
        ├── property_card.dart         # item de liste
        ├── property_form.dart         # champs partagés (extrait)
        └── archive_confirm_dialog.dart
```

### Nouveaux fichiers — détail

| Fichier | Rôle |
|---|---|
| `domain/property.dart` | `@freezed class Property` : `id`, `landlordId`, `name`, `address`, `type` (`PropertyType`), `surfaceM2` (`double?`), `createdAt`, `updatedAt`. JSON via `json_serializable` avec `fieldRename: FieldRename.snake`. |
| `domain/property_type.dart` | `enum PropertyType { appartement, maison, studio, autre }` + `extension PropertyTypeX { String get labelFr; String get sqlValue; static PropertyType fromSql(String) }`. Cf. Q5. |
| `domain/property_form_state.dart` | `@freezed sealed class PropertyFormState` union : `idle`, `submitting`, `success(Property created)`, `error(String message)`. Mêmes conventions que `LoginFormState`. |
| `data/property_repository.dart` | Interface `PropertyRepository` + impl `SupabasePropertyRepository` utilisant `Db.from('properties')` et `Db.rpc('soft_delete_property', params: {'p_id': id})`. |
| `application/properties_list_provider.dart` | `AsyncNotifierProvider<PropertiesListNotifier, List<Property>>` — méthode `refresh()` exposée pour rappel après création/édition/archivage. |
| `application/property_detail_provider.dart` | `AsyncNotifierProviderFamily<PropertyDetailNotifier, Property, String>` (id en argument). Renvoie une exception `PropertyNotFound` si la query renvoie 0 ligne (RLS ou archivage). |
| `application/property_form_controller.dart` | `StateNotifier<PropertyFormState>` avec `submit({Property? initial, required values…})` — distingue create vs update sur `initial == null`. |
| `presentation/properties_list_page.dart` | Liste scrollable, état vide explicite, FAB "Ajouter un bien". Bouton retour Dashboard si on vient de là. |
| `presentation/property_detail_page.dart` | Affiche les champs en lecture + boutons "Modifier" (push `/properties/:id/edit` ou toggle, cf. Q1) et "Archiver". Section "Baux actifs" stub vide en V1 (texte "Disponible après FEAT-005"). |
| `presentation/property_form_page.dart` | Reçoit `Property? initial`. Si null → mode create (titre "Nouveau bien"). Sinon → mode edit (titre "Modifier le bien", champs pré-remplis). Soumission délègue au controller. |
| `presentation/widgets/property_card.dart` | Card cliquable (nom, type traduit, adresse tronquée, surface). |
| `presentation/widgets/property_form.dart` | `TextField` nom, `TextField` adresse multiline, `DropdownButtonFormField<PropertyType>`, `TextField` surface (numérique). Validation inline à la perte de focus. |
| `presentation/widgets/archive_confirm_dialog.dart` | `AlertDialog` paramétré ("Archiver ce bien ?", message variable selon bail actif, bouton "Annuler" / "Archiver" destructif). |

### Modifications

| Fichier | Changement |
|---|---|
| `lib/core/router/app_router.dart` | Ajout des routes `/properties`, `/properties/new`, `/properties/:id`, `/properties/:id/edit` (cf. Q1). Aucune logique de redirect supplémentaire (les routes sont sous garde authentifiée par défaut). |
| `lib/features/dashboard/presentation/dashboard_page.dart` | Ajout d'une carte/bouton "Mes biens" qui `context.go('/properties')`. Cf. Q10 — option ListTile sur le body actuel, **pas de drawer**. |
| `lib/core/utils/` | Ajout de `surface_validator.dart` (parse FR `1,5` ↔ `1.5`, valide > 0, ≤ 9999.99) et `property_form_validators.dart` (nom et adresse non vides après trim). Pattern identique à `email_validator.dart` : classes statiques, zéro dépendance Flutter, testables. |

### Providers Riverpod

| Provider | Type | Rôle |
|---|---|---|
| `propertyRepositoryProvider` | `Provider<PropertyRepository>` | Expose `SupabasePropertyRepository` (instancié avec `Db`). |
| `propertiesListProvider` | `AsyncNotifierProvider<PropertiesListNotifier, List<Property>>` | Liste des biens du landlord courant (tri `created_at DESC`). |
| `propertyDetailProvider(id)` | `AsyncNotifierProviderFamily<PropertyDetailNotifier, Property, String>` | Fiche bien — invalidé après update/archive. |
| `propertyFormControllerProvider` | `StateNotifierProvider.autoDispose<PropertyFormController, PropertyFormState>` | Contrôle le formulaire. `autoDispose` pour reset entre 2 ouvertures. |

### Routes GoRouter à ajouter

```dart
GoRoute(path: '/properties', builder: (_, __) => const PropertiesListPage()),
GoRoute(path: '/properties/new', builder: (_, __) => const PropertyFormPage(initial: null)),
GoRoute(
  path: '/properties/:id',
  builder: (_, state) => PropertyDetailPage(id: state.pathParameters['id']!),
),
GoRoute(
  path: '/properties/:id/edit',
  builder: (_, state) => PropertyFormPage.edit(id: state.pathParameters['id']!),
),
```

> Note : `PropertyFormPage.edit(id:)` lit `propertyDetailProvider(id)` puis passe la `Property` chargée en `initial` (loader async pendant ce temps).

## Décisions de design

### Q1 — Route d'édition séparée vs mode édition sur la fiche

**Recommandation : route séparée `/properties/:id/edit`.**

- **UX** : un seul écran « lecture seule » plus lisible (typo, espacements aérés) qu'un écran qui bascule entre lecture et édition. Évite l'ambiguïté "je viens de cliquer Modifier, suis-je en train d'éditer ?".
- **State** : sépare proprement les responsabilités (`propertyDetailProvider` lit ; `propertyFormControllerProvider` écrit). Pas de risque de désynchroniser un controller en mode "view".
- **Deep-link** : URL `/properties/:id/edit` partageable / bookmarkable / restaurable après refresh navigateur. Sur une PWA c'est un gain réel.
- **Coût** : nul — `PropertyFormPage` est déjà partagée create/edit (cf. Q2).

### Q2 — Widget formulaire create vs edit

**Recommandation : 1 widget partagé `PropertyFormPage` avec paramètre `Property? initial`.**

Les champs, validateurs, layout et logique de soumission sont identiques à 95%. La seule différence est l'appel repo final (`create` vs `update`), encapsulé dans `PropertyFormController.submit()`. Deux widgets quasi-identiques violeraient DRY et multiplieraient les chances de drift. Le titre AppBar et le label du bouton de soumission sont dérivés de `initial == null`.

### Q3 — Avertissement bail actif avant archivage

**Recommandation : Option B (implémenter la query `leases`).**

Justification :
- La table `leases` existe déjà (FEAT-002), avec RLS et l'index partiel `idx_public_leases_status_active_partial`. La query est *triviale*.
- L'absence d'écran CRUD baux (FEAT-005) ne bloque rien : on peut très bien insérer des données via SQL pour QA, ou attendre que FEAT-005 alimente la table.
- Sauter complètement la vérif (Option A) crée une dette UX : un utilisateur archive son seul bien et ses quittances futures pointent dans le vide. Le surcoût est de ~10 lignes Dart.
- L'option C (dialog non-conditionnel) génère du bruit cognitif et désensibilise l'utilisateur ; à éviter.

**Implémentation** : dans `PropertyRepository`, méthode `hasActiveLease(String propertyId) → Future<bool>` :

```dart
final rows = await Db.from('leases')
    .select('id')
    .eq('property_id', propertyId)
    .eq('status', 'active')
    .filter('deleted_at', 'is', null)
    .limit(1);
return rows.isNotEmpty;
```

Le widget `ArchiveConfirmDialog` affiche le message renforcé "Ce bien a un bail actif. Êtes-vous sûr ?" si `hasActiveLease == true`, sinon le message standard.

### Q4 — Modèle Dart Property

**Recommandation : freezed + json_serializable**, cohérent avec `LoginFormState`.

Mapping JSON : `@JsonSerializable(fieldRename: FieldRename.snake)` aligne directement sur les colonnes Postgres (`landlord_id`, `surface_m2`, `created_at`…). On évite le code de conversion manuel à entretenir.

```dart
@freezed
class Property with _$Property {
  const factory Property({
    required String id,
    required String landlordId,
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Property;

  factory Property.fromJson(Map<String, dynamic> json) => _$PropertyFromJson(json);
}
```

> Conversion `PropertyType` : `@JsonKey(fromJson: PropertyType.fromSql, toJson: _typeToSql)` (helpers dans `property_type.dart`).
>
> Pour la création (sans id/timestamps), on n'utilise PAS `Property` directement → on passe un `PropertyDraft` (POJO simple) au repo, qui construit le `Map<String, dynamic>` minimal pour Supabase.

### Q5 — Enum `type`

**Recommandation : enum Dart fermé + extension localisation FR.**

```dart
enum PropertyType {
  appartement,
  maison,
  studio,
  autre;

  String get labelFr => switch (this) {
    PropertyType.appartement => 'Appartement',
    PropertyType.maison => 'Maison',
    PropertyType.studio => 'Studio',
    PropertyType.autre => 'Autre',
  };

  String get sqlValue => name; // 'appartement' etc. — déjà aligné

  static PropertyType fromSql(String value) =>
      PropertyType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => PropertyType.autre, // tolérance si nouvelle valeur SQL un jour
      );
}
```

Avantages : le CHECK SQL et le `Dropdown` Flutter ne peuvent plus diverger (compilation casse si désync). Localisation FR isolée et testable. Pas de magic string dans les widgets.

### Q6 — Surface (numeric(6,2))

**Recommandation : `double?` en Dart, parsing depuis input FR (virgule autorisée), formattage à l'affichage via `intl` (`NumberFormat.decimalPattern('fr_FR')`).**

Pourquoi `double` et non `Decimal` :
- `numeric(6,2)` borne à 9999.99 — la précision double est largement suffisante (pas d'arithmétique financière ici, juste de l'affichage).
- `Decimal` (package) introduit une dépendance + boilerplate sérialisation qui ne se justifie que pour `rent_amount` (FEAT-005), pas pour une surface.

Validation (`surface_validator.dart`) :
1. trim. Si vide → valide (champ optionnel, on envoie `null`).
2. Remplace `,` par `.`.
3. `double.tryParse` ; si null → erreur "Surface invalide".
4. Si ≤ 0 → "La surface doit être positive".
5. Si > 9999.99 → "Surface maximale 9999,99 m²".
6. Renvoie `double?`.

### Q7 — Pagination

**Recommandation : tout charger en V1, plafond de garde-fou à 200 lignes.**

- Cible utilisateurs : particuliers, 1-20 biens dans 95% des cas.
- Pagination complexifie le state (curseur, loading footer, refresh partiel) pour zéro gain perceptible.
- Garde-fou : `.limit(200)` dans la requête + bandeau d'info si on atteint la limite (improbable mais signaux clairs pour debug futur).
- Pagination réelle = post-MVP, à introduire avec un `infinite_scroll_pagination` si besoin (FEAT post-V1).

### Q8 — Soft-delete via RPC

**Confirmé.** L'UPDATE direct sur `deleted_at` est bloqué par le trigger `tr_01_prevent_protected_columns_change_properties` (ERRCODE 42501). On DOIT passer par la RPC.

Appel depuis Dart (via `Db.rpc` pour respect du schéma actif) :

```dart
@override
Future<void> archive(String id) async {
  await Db.rpc('soft_delete_property', params: {'p_id': id});
}
```

La RPC est `SECURITY DEFINER` avec ownership check `WHERE id = p_id AND landlord_id = auth.uid()` ; si le bien n'appartient pas au user, l'appel ne fait rien (0 row affected). Le repo doit considérer un retour vide comme un succès silencieux (le bien disparaît de la liste après refresh — pas besoin de surfacer l'erreur "pas le proprio" qui n'arrivera jamais via l'UI).

### Q9 — Gestion d'erreur standardisée

**Recommandation : aligner sur `auth_controller.dart`.**

Pour les actions utilisateur (create, update, archive) :
- `PropertyFormController` expose `PropertyFormState.error(String message)` consommé inline dans la page (pattern login).
- Un helper `_mapPostgrestError(PostgrestException e) → String` traduit les erreurs courantes (RLS violation, check_violation surface, etc.) en français lisible.
- En complément, un `ScaffoldMessenger.of(context).showSnackBar()` toast vert "Bien créé" / "Modifications enregistrées" / "Bien archivé" sur succès (cf. acceptance criteria).

Pour les lectures (`propertiesListProvider`, `propertyDetailProvider`) :
- Pattern `AsyncValue.when(data, loading, error)` direct dans la page — affiche un `CircularProgressIndicator` ou un `ErrorRetryView` (à créer si pas déjà là — sinon `Text` simple suffit en V1).

### Q10 — Navigation principale

**Recommandation : ajouter une `ListTile` "Mes biens" dans le body du Dashboard actuel + bouton retour Dashboard dans l'AppBar de `/properties`. Pas de drawer pour le MVP.**

Justification :
- Le dashboard est aujourd'hui un stub avec seulement `Text('Tableau de bord…')`. Le transformer en hub avec 1-N `ListTile` ("Mes biens", futur "Mes locataires", "Mes baux") est le pattern le moins lourd et le plus extensible.
- Un drawer ajoute du code (Drawer widget, items, dispatch) pour 1 seule entrée en V1.
- Une bottom nav suppose ≥ 3 sections dès la sortie ; on n'y est pas.
- Quand on aura 4-5 sections (post-FEAT-005), on bascule sur drawer ou nav latérale responsive en 30 minutes.

## Validation

| Champ | Règle | Helper |
|---|---|---|
| `name` | `trim().isNotEmpty` | `property_form_validators.dart#validateName` |
| `address` | `trim().isNotEmpty` | `property_form_validators.dart#validateAddress` |
| `type` | requis, valeur de l'enum (dropdown ⇒ toujours valide) | N/A (sécurisé par le type) |
| `surface_m2` | optionnel ; si présent, > 0 et ≤ 9999.99, accepte `,` ou `.` | `surface_validator.dart#parse` |

Validation déclenchée :
- À la perte de focus (`onChanged` met le champ "touched", affichage de l'erreur si invalide).
- Au tap "Soumettre" : tous les champs sont marqués touched, le bouton ne déclenche l'appel repo QUE si tout est valide (sinon focus du 1er invalide).

## Testing strategy

### Tests unitaires (`test/unit/`)

- `property_test.dart` : sérialisation Property ↔ JSON (round-trip, surface null, dates ISO).
- `property_type_test.dart` : `fromSql` (cas connus + fallback `autre`), `labelFr`, `sqlValue`.
- `surface_validator_test.dart` : virgule, point, vide, négatif, > 9999.99, espaces.
- `property_form_validators_test.dart` : nom/adresse vide, espaces uniquement, valeur OK.

### Tests widget (`test/widget/`)

- `properties_list_page_test.dart` : état vide (texte + bouton Ajouter), liste avec 2 items, AsyncValue loading/error.
- `property_form_page_test.dart` :
  - mode create : tous champs vides, erreurs inline sur soumission incomplète, soumission valide appelle le controller.
  - mode edit : champs pré-remplis depuis `initial`.
- `archive_confirm_dialog_test.dart` : 2 variantes de message (avec/sans bail actif), bouton "Annuler" ferme sans action.

### Tests RLS (`supabase/tests/`)

Déjà couverts par FEAT-002 (`rls_properties.sql`, 20 tests). **Rien à ajouter.** Si toutefois on doute, ajouter un test manuel "deep-link cross-user" dans le QA manuel ci-dessous.

### QA manuel

1. Créer 2 comptes A et B (magic link).
2. Avec A : créer 3 biens variés (Appartement avec surface, Studio sans surface, Maison).
3. Avec A : modifier le 2e, vérifier que `updated_at` change (visible dans la fiche si on l'affiche).
4. Avec A : archiver le 3e, vérifier qu'il disparaît de la liste.
5. Insérer manuellement (via SQL ou via FEAT-005 plus tard) un lease `status='active'` sur le 1er bien. Tenter de l'archiver — vérifier l'avertissement renforcé.
6. Avec B connecté : tenter `/properties/<id-de-A>` → page "Bien introuvable" (pas de leak).
7. Avec B : créer un bien — vérifier qu'il ne voit que le sien.
8. Refresh navigateur sur `/properties/:id` → la session est restaurée, le bien s'affiche.

## Step-by-step execution order

1. **`supabase-dev`** — N/A (aucune migration ; éventuellement seed dev pour QA).
2. **`flutter-dev`** :
   1. `domain/` : `property_type.dart`, `property.dart`, `property_form_state.dart` → `flutter pub run build_runner build`.
   2. `core/utils/` : `surface_validator.dart`, `property_form_validators.dart`.
   3. `data/property_repository.dart` (interface + impl).
   4. `application/` : 3 providers.
   5. `presentation/` : list page, form page, detail page, widgets.
   6. `core/router/app_router.dart` : ajout des 4 routes.
   7. `dashboard_page.dart` : entrée "Mes biens".
3. **`qa-tester`** — exécute les tests Dart + le QA manuel ci-dessus.
4. **`code-reviewer`** — vérifie conformité aux conventions (taille widgets, providers, naming).
5. **`security-auditor`** — vérifie qu'aucun INSERT n'envoie `landlord_id` côté client, qu'aucun UPDATE ne touche `deleted_at`, que la RPC est bien utilisée pour l'archive.
6. **`state-keeper`** — met à jour `docs/state/ROUTES.md` et `FEATURES.md`.

## Risques

| Risque | Probabilité | Mitigation |
|---|---|---|
| **State stale après archive/edit** : la liste ou la fiche affichent encore l'ancien état. | Moyenne | Après chaque action réussie, le controller appelle `ref.invalidate(propertiesListProvider)` et `ref.invalidate(propertyDetailProvider(id))`. À documenter dans le code. |
| **Deep-link sur `/properties/:id` non possédé ou archivé** : 0 ligne renvoyée par RLS. | Certain (UX) | `propertyDetailProvider` distingue "row absente" et "erreur réseau", affiche "Bien introuvable" propre. Pas d'exception non-catchée. |
| **Erreur RPC `soft_delete_property` silencieuse** (mauvais id, bien non-possédé) | Faible | Considérer 0 row affected comme succès silencieux + refresh liste. Logger en `warning` si l'id passé n'apparaît pas dans le state local après refresh. |
| **Trigger `prevent_protected_columns_change` bloque un UPDATE legitime** si on inclut accidentellement `created_at` ou `updated_at` dans le payload | Moyenne | Le repo construit explicitement le `Map` avec **seulement** les champs métier (name, address, type, surface_m2). À noter en commentaire. |
| **Parsing surface FR `1,5` cassé en build release** (locale différente du runtime) | Faible | Helper `surface_validator` fait la conversion `,→.` à la main, indépendant de la locale. |
| **Désynchronisation enum Dart / CHECK SQL** si quelqu'un ajoute un type côté SQL sans toucher Dart | Faible | `fromSql` a un fallback `autre` (graceful). Documenter la double-source de vérité dans le code de l'enum. |
| **Pas de moyen de "désarchiver" un bien en V1** | Acceptée | Hors scope V1. À traiter si demandé : RPC `restore_property` (à créer post-MVP). |

## Questions critiques (arbitrage utilisateur)

1. **Q3 / Bail actif** : confirmer l'**Option B** (query légère sur `leases` malgré FEAT-005 pas encore livrée) au lieu de skipper complètement la vérif. Surcoût : ~10 lignes. Bénéfice : pas de dette UX/QA à reprendre en FEAT-005. → **Décision attendue.**

2. **Q10 / Navigation** : valider qu'on enrichit le Dashboard avec une `ListTile` "Mes biens" plutôt que d'introduire un drawer dès maintenant. Si le PO préfère drawer dès FEAT-003 (pour préparer FEAT-004/005), on le crée — coût marginal +1h.

3. **Filtre "Afficher archivés"** : la story dit "optionnel en V1". → **Décision attendue** : on l'embarque (5 lignes : toggle + `.filter('deleted_at', ...)`) ou on le reporte ? Recommandation : reporter, on ne sait pas encore le besoin réel.

4. **Champ supplémentaire ?** : la story ne mentionne pas de description longue, photos, références cadastrales. Pas de demande explicite, on n'en ajoute pas. À confirmer.

5. **Tri** : story dit `created_at DESC`. OK pour V1. Tri alphabétique optionnel ? → Recommandation : non, V1 minimal.
