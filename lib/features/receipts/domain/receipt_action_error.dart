/// Erreurs des flows d'action sur une quittance (génération, annulation,
/// partage), indépendantes de la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : [ReceiptGenerationState.error] et
/// [ShareReceiptState.error] (freezed, générés via `build_runner`) ainsi que
/// `VoidReceiptError` (sealed class manuelle) portent chacun un champ
/// `message` de type `String` — les régénérer avec un type enum est hors
/// périmètre de cette extraction (nécessite de relancer `build_runner` pour
/// les deux states freezed, non disponible dans cet environnement). Pattern
/// retenu, identique à `TenantSubmitError`
/// (`lib/features/tenants/domain/tenant_submit_error.dart`) : les
/// contrôleurs (`GenerateReceiptController`, `VoidReceiptController`,
/// `ShareReceiptController`) stockent le **nom** de cet enum
/// (`ReceiptActionError.name`, une clé technique stable, jamais un message
/// FR) dans le champ `message` de leur état d'erreur ; la couche
/// présentation (`receipt_action_error_l10n.dart`) le reconvertit via
/// [ReceiptActionErrorL10n] pour l'afficher dans un SnackBar.
///
/// Un seul enum est partagé par les 3 flows (génération, annulation,
/// partage) plutôt que trois enums quasi identiques, car `permissionDenied`
/// et `unknown` portent exactement le même message dans le code d'origine
/// pour les trois contrôleurs.
enum ReceiptActionError {
  /// Action refusée (permission-denied / unauthenticated) — génération ou
  /// annulation.
  permissionDenied,

  /// Génération : aucun paiement trouvé pour cette période, ou bail
  /// invalide (failed-precondition).
  noPaymentForPeriod,

  /// Génération : bail ou paiements introuvables (not-found).
  leaseOrPaymentsNotFound,

  /// Génération : échec générique (réseau, Cloud Function, rendu PDF).
  generationFailed,

  /// Annulation : quittance introuvable (not-found).
  receiptNotFound,

  /// Annulation : quittance déjà annulée ou non annulable
  /// (failed-precondition).
  alreadyVoidedOrInvalid,

  /// Annulation : échec générique.
  voidFailed,

  /// Partage : échec générique (Web Share API, réseau, presse-papier).
  shareFailed,

  /// Erreur générique inattendue, commune aux 3 flows.
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans le champ `message` de
  /// l'état d'erreur — retourne [unknown] si absent/invalide (ne doit
  /// jamais arriver en pratique, filet de sécurité défensif).
  static ReceiptActionError fromCode(String code) {
    return ReceiptActionError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => ReceiptActionError.unknown,
    );
  }
}
