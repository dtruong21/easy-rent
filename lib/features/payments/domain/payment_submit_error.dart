/// Erreurs du flow de soumission (création/édition/archivage) d'un paiement,
/// indépendantes de la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : `PaymentFormState.error` (freezed, généré via
/// `build_runner`) porte un champ `message` de type `String` — le régénérer
/// avec un type enum est hors périmètre (nécessite de relancer
/// `build_runner`, non disponible dans cet environnement). Pattern retenu,
/// identique à `TenantSubmitError`
/// (`lib/features/tenants/domain/tenant_submit_error.dart`) et
/// `ExpenseSubmitError`
/// (`lib/features/expenses/domain/expense_submit_error.dart`) :
/// [PaymentFormController]
/// (`lib/features/payments/application/payment_form_controller.dart`) stocke
/// le **nom** de cet enum (`PaymentSubmitError.name`, une clé technique
/// stable, jamais un message FR) dans `PaymentFormState.error.message` ; la
/// couche présentation (`payment_submit_error_l10n.dart`) le reconvertit via
/// [PaymentSubmitErrorL10n] pour l'afficher.
enum PaymentSubmitError {
  /// Le paiement est introuvable (a peut-être été archivé entre-temps).
  notFound,

  /// Action refusée (permission-denied / unauthenticated).
  permissionDenied,

  /// Précondition serveur non satisfaite — état du paiement invalide
  /// (failed-precondition).
  invalidState,

  /// Service indisponible ou délai dépassé (unavailable / deadline-exceeded).
  serviceUnavailable,

  /// Erreur réseau / Callable générique lors de la sauvegarde.
  saveFailed,

  /// Erreur générique inattendue.
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `PaymentFormState.error.message` — retourne [unknown] si
  /// absent/invalide (ne doit jamais arriver en pratique, filet de sécurité
  /// défensif).
  static PaymentSubmitError fromCode(String code) {
    return PaymentSubmitError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => PaymentSubmitError.unknown,
    );
  }
}
