/// Erreurs du flow de soumission (création/édition/clôture) d'un bail,
/// indépendantes de la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : `LeaseFormState.error` (freezed, généré via
/// `build_runner`) porte un champ `message` de type `String` — le régénérer
/// avec un type enum est hors périmètre (nécessite de relancer
/// `build_runner`, non disponible dans cet environnement). Pattern retenu,
/// identique à `TenantSubmitError`
/// (`lib/features/tenants/domain/tenant_submit_error.dart`) et
/// `PaymentSubmitError`
/// (`lib/features/payments/domain/payment_submit_error.dart`) :
/// [LeaseFormController]
/// (`lib/features/leases/application/lease_form_controller.dart`) stocke le
/// **nom** de cet enum (`LeaseSubmitError.name`, une clé technique stable,
/// jamais un message FR) dans `LeaseFormState.error.message` ; la couche
/// présentation (`lease_submit_error_l10n.dart`) le reconvertit via
/// [LeaseSubmitErrorL10n] pour l'afficher.
enum LeaseSubmitError {
  /// Le bail est introuvable (a peut-être été archivé entre-temps).
  notFound,

  /// Le bail est déjà clôturé (`LeaseAlreadyClosedException`).
  alreadyClosed,

  /// Le bien ou le locataire sélectionné n'appartient pas au bailleur
  /// courant (garde serveur `property not owned` / `tenant not owned`).
  propertyOrTenantNotOwned,

  /// Le bien ou le locataire sélectionné a été archivé entre-temps
  /// (`property is deleted` / `tenant is deleted`).
  propertyOrTenantArchived,

  /// Action refusée (permission-denied / unauthenticated).
  permissionDenied,

  /// Précondition serveur non satisfaite — état du bail invalide
  /// (failed-precondition, hors [alreadyClosed]).
  invalidState,

  /// Service indisponible ou délai dépassé (unavailable / deadline-exceeded).
  serviceUnavailable,

  /// Erreur réseau / Callable générique lors de la sauvegarde.
  saveFailed,

  /// Erreur générique inattendue.
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `LeaseFormState.error.message` — retourne [unknown] si absent/invalide
  /// (ne doit jamais arriver en pratique, filet de sécurité défensif).
  static LeaseSubmitError fromCode(String code) {
    return LeaseSubmitError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => LeaseSubmitError.unknown,
    );
  }
}
