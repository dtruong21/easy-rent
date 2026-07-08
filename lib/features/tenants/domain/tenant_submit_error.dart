/// Erreurs de soumission du formulaire locataire, indépendantes de la
/// locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : [TenantFormState.error] (freezed, généré via
/// `build_runner`) porte un champ `message` de type `String` — le
/// régénérer avec un type enum est hors périmètre de cette extraction
/// (nécessite de relancer `build_runner`, non disponible dans cet
/// environnement). Pattern retenu : [TenantFormController] stocke le
/// **nom** de cet enum (`TenantSubmitError.name`, une clé technique stable,
/// jamais un message FR) dans `TenantFormState.error.message` ; la couche
/// présentation (`tenant_form_page.dart`) le reconvertit via
/// [TenantSubmitErrorL10n] pour l'afficher.
///
/// Mêmes garanties que le pattern `ValidationError` du domaine partagé
/// (`lib/core/validation/validation_error.dart`) : aucune dépendance à
/// `BuildContext`/`AppLocalizations` ici.
enum TenantSubmitError {
  /// Le locataire a des baux actifs — l'archivage a été refusé côté backend.
  hasActiveLeases,

  /// Action refusée (permission-denied / unauthenticated).
  permissionDenied,

  /// Service indisponible ou délai dépassé (unavailable / deadline-exceeded).
  serviceUnavailable,

  /// Le locataire est introuvable (a peut-être été archivé entre-temps).
  notFound,

  /// Erreur réseau / Firestore générique lors de la sauvegarde.
  saveFailed,

  /// Erreur générique inattendue.
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `TenantFormState.error.message` — retourne [unknown] si absent/invalide
  /// (ne doit jamais arriver en pratique, filet de sécurité défensif).
  static TenantSubmitError fromCode(String code) {
    return TenantSubmitError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => TenantSubmitError.unknown,
    );
  }
}
