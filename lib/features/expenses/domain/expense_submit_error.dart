/// Erreurs du flow de soumission (création/édition/archivage) d'une dépense,
/// indépendantes de la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : `ExpenseFormState.error` (freezed, généré via
/// `build_runner`) porte un champ `message` de type `String` — le régénérer
/// avec un type enum est hors périmètre de cette extraction (nécessite de
/// relancer `build_runner`, non disponible dans cet environnement). Pattern
/// retenu, identique à `TenantSubmitError`
/// (`lib/features/tenants/domain/tenant_submit_error.dart`) et
/// `ReceiptActionError`
/// (`lib/features/receipts/domain/receipt_action_error.dart`) :
/// [ExpenseFormController] (`lib/features/expenses/application/expense_form_controller.dart`)
/// stocke le **nom** de cet enum (`ExpenseSubmitError.name`, une clé
/// technique stable, jamais un message FR) dans
/// `ExpenseFormState.error.message` ; la couche présentation
/// (`expense_submit_error_l10n.dart`) le reconvertit via
/// [ExpenseSubmitErrorL10n] pour l'afficher.
enum ExpenseSubmitError {
  /// La nature de la dépense impose une catégorie non modifiable
  /// (`category_locked_for_nature`, décret n°87-713) — le client a tenté de
  /// forcer une catégorie sur une nature verrouillée.
  categoryLockedForNature,

  /// Action refusée (permission-denied / unauthenticated).
  permissionDenied,

  /// Précondition serveur non satisfaite — champs invalides
  /// (failed-precondition, hors `category_locked_for_nature`).
  invalidFields,

  /// Service indisponible ou délai dépassé (unavailable / deadline-exceeded).
  serviceUnavailable,

  /// La dépense est introuvable (a peut-être été archivée entre-temps).
  notFound,

  /// Erreur réseau / Callable générique lors de la sauvegarde.
  saveFailed,

  /// Erreur générique inattendue.
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `ExpenseFormState.error.message` — retourne [unknown] si
  /// absent/invalide (ne doit jamais arriver en pratique, filet de sécurité
  /// défensif).
  static ExpenseSubmitError fromCode(String code) {
    return ExpenseSubmitError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => ExpenseSubmitError.unknown,
    );
  }
}
