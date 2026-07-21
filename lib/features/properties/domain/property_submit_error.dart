/// Erreurs du flow de soumission (création/édition) d'un bien, indépendantes
/// de la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : `PropertyFormState.error` (freezed, généré via
/// `build_runner`) porte un champ `message` de type `String` — le régénérer
/// avec un type enum est hors périmètre (nécessite de relancer
/// `build_runner`, non disponible dans cet environnement). Pattern retenu,
/// identique à `TenantSubmitError`
/// (`lib/features/tenants/domain/tenant_submit_error.dart`) et
/// `LeaseSubmitError`
/// (`lib/features/leases/domain/lease_submit_error.dart`) :
/// [PropertyFormController]
/// (`lib/features/properties/application/property_form_controller.dart`)
/// stocke le **nom** de cet enum (`PropertySubmitError.name`, une clé
/// technique stable, jamais un message FR) dans
/// `PropertyFormState.error.message` ; la couche présentation
/// (`property_submit_error_l10n.dart`) le reconvertit via
/// [PropertySubmitErrorL10n] pour l'afficher.
enum PropertySubmitError {
  /// Le bien est introuvable (a peut-être été archivé entre-temps).
  notFound,

  /// Le bien a des baux actifs — l'archivage a été refusé serveur
  /// (`property_has_active_leases`).
  hasActiveLeases,

  /// Plafond de biens de l'offre gratuite atteint (FEAT-044) — la Callable
  /// `createProperty` a refusé la création (`resource-exhausted` /
  /// `property_limit_reached`). Invite à passer à l'offre Pro.
  limitReached,

  /// Action refusée (permission-denied / unauthenticated).
  permissionDenied,

  /// Service indisponible ou délai dépassé (unavailable / deadline-exceeded).
  serviceUnavailable,

  /// Erreur générique de connexion Firestore (`FirebaseException` hors
  /// Callable) — vérifiez la connexion réseau.
  connectionError,

  /// Erreur réseau / Callable générique lors de la sauvegarde.
  saveFailed,

  /// Erreur générique inattendue.
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `PropertyFormState.error.message` — retourne [unknown] si
  /// absent/invalide (ne doit jamais arriver en pratique, filet de sécurité
  /// défensif).
  static PropertySubmitError fromCode(String code) {
    return PropertySubmitError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => PropertySubmitError.unknown,
    );
  }
}
