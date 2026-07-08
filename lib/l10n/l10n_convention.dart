/// Convention de nommage des clés ARB — FEAT-043 (i18n).
///
/// Ce fichier ne contient **aucun code** : c'est la documentation de
/// référence pour ajouter des clés dans `app_en.arb` (template gen_l10n,
/// source de vérité) et `app_fr.arb`. À lire avant toute extraction de
/// chaîne en dur vers l10n (voir `docs/plans/FEAT-043-i18n.md` pour le plan
/// complet et le phasage par module).
///
/// ## Règles
///
/// 1. **camelCase préfixé par domaine** : `<domaine><Suite en PascalCase>`.
///    Exemples : `authLoginTitle`, `leasesFormRentLabel`, `commonSave`.
/// 2. **`common*`** : chaînes transverses partagées par 2+ modules (actions
///    génériques Enregistrer/Annuler/Supprimer/Modifier/Retour/Confirmer,
///    libellés génériques d'état chargement/erreur). Ne jamais dupliquer une
///    chaîne `common*` sous un préfixe de module — grep `common` avant
///    d'ajouter une nouvelle clé pour éviter les doublons.
/// 3. **`nav*`** : libellés de destination de la navigation shell (barre du
///    bas < 600px / rail ≥ 600px), une clé par branche (`navHome`,
///    `navProperties`, `navTenants`, `navLeases`, `navProfile`).
/// 4. **`<module>*`** : un préfixe par dossier `lib/features/<module>`
///    (`auth*`, `leases*`, `properties*`, `tenants*`, `expenses*`,
///    `dashboard*`, `profile*`, `receipts*`, `payments*`, `documents*`,
///    `simulator*`, `chargeRegularization*`, `support*`, `landing*`,
///    `pwa*`). Sous-scoper avec un second segment si utile pour la
///    lisibilité : `leasesFormRentLabel`, `leasesFilterLate`,
///    `leasesStatusActive`, `expensesNatureWorks`.
/// 5. **`validation*`** : messages d'erreur de validateurs, surfacés depuis
///    un enum d'erreur (pattern ci-dessous) — les validateurs restent des
///    fonctions pures sans dépendance à `BuildContext`/`AppLocalizations` ;
///    seule la couche présentation mappe l'enum vers la clé ARB.
/// 6. **Metadata `@key` obligatoire** dans le template (`app_en.arb`) :
///    `description` non vide (contexte traducteur) + `placeholders` typés
///    explicitement (`DateTime`/`int`/`String`, avec `format:` pour les
///    types formatés) dès qu'une clé est interpolée. `app_fr.arb` n'a besoin
///    d'aucune metadata (seul le template en exige).
/// 7. **Hors périmètre (ne jamais ajouter de clé ARB)** : contenu des
///    documents légaux — quittance PDF (`receipt_pdf_renderer.dart`), avis
///    de régularisation PDF (`charge_regularization_pdf_renderer.dart`),
///    CGU (`terms_page.dart`), politique de confidentialité
///    (`privacy_page.dart`). Ces documents restent 100 % français (valeur
///    légale, loi du 6 juillet 1989 + décret 87-713 + RGPD). Seul le
///    « chrome » UI autour (boutons, titres de page, SnackBars) est
///    traduisible.
/// 8. **Devise €** : la monnaie reste l'euro dans les deux locales — seuls
///    les séparateurs de nombres/dates suivent la locale active (`intl`).
///    Ne jamais introduire de symbole `$`.
///
/// ## Deux patterns de refactor établis (FEAT-043 foundation)
///
/// ### (a) Validator → enum d'erreur mappé en présentation
///
/// Les validateurs (`lib/core/utils/*_validators.dart`) sont des fonctions
/// pures, testées sans `BuildContext` ni `AppLocalizations`. Ils NE
/// retournent PAS de `String` en dur : ils retournent un
/// `ValidationError?` (enum, `lib/core/validation/validation_error.dart`).
/// La couche présentation (widget) mappe l'enum vers la chaîne localisée via
/// `ValidationErrorL10n.message(context)` (extension dans
/// `lib/core/validation/validation_error_l10n.dart`).
///
/// ```dart
/// // domaine (pur, testable sans contexte) :
/// static ValidationError? validateEmailPattern(String? value) {
///   if (value == null || value.trim().isEmpty) {
///     return ValidationError.required;
///   }
///   if (!EmailValidator.isValid(value)) {
///     return ValidationError.invalidEmail;
///   }
///   return null;
/// }
///
/// // présentation (widget, a un BuildContext) :
/// validator: (v) => EmailFormValidators.validateEmailPattern(v)
///     ?.message(context),
/// ```
///
/// ### (b) Enum métier → mapping l10n en présentation
///
/// Les enums métier du domaine (ex. `LeaseFilter`) ne portent plus de
/// libellé FR en dur (`labelFr`). Le domaine expose l'enum nu ; un mapping
/// `label(BuildContext)` vit dans la couche présentation (extension dédiée,
/// colocalisée avec les widgets qui l'utilisent) et route vers
/// `context.l10n.<clé>` (raccourci `AppLocalizations.of(context)`, voir
/// `lib/core/i18n/l10n_extensions.dart`).
///
/// ```dart
/// // domaine (lib/features/leases/domain/lease_filter.dart) : enum nu,
/// // AUCUN libellé FR en dur.
/// enum LeaseFilter { all, active, renewable, late, terminated }
///
/// // présentation (lib/features/leases/presentation/lease_filter_l10n.dart) :
/// extension LeaseFilterL10n on LeaseFilter {
///   String label(BuildContext context) {
///     final l10n = context.l10n;
///     return switch (this) {
///       LeaseFilter.all => l10n.leasesFilterAll,
///       LeaseFilter.active => l10n.leasesFilterActive,
///       LeaseFilter.renewable => l10n.leasesFilterRenewable,
///       LeaseFilter.late => l10n.leasesFilterLate,
///       LeaseFilter.terminated => l10n.leasesFilterTerminated,
///     };
///   }
/// }
/// ```
///
/// Ce même pattern s'applique aux autres enums avec `labelFr` en dur
/// identifiés par le plan (`ExpenseNature`, statuts de baux, catégories de
/// documents, `ChargeMode`, etc.) — à traiter module par module en Phase 1+
/// (hors périmètre de ce ticket foundation).
///
/// ## Conflits de merge (travail parallèle par module)
///
/// Chaque module ajoute ses clés dans une section délimitée par des
/// commentaires ARB (`// --- <module> ---`) pour limiter les conflits de
/// merge sur `app_en.arb`/`app_fr.arb`. Un test (`test/l10n/arb_parity_test.dart`)
/// vérifie que les deux fichiers ont exactement le même jeu de clés.
library;
