/// Motif d'échec du flow « générer + partager l'avis de régularisation »,
/// indépendant de la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : [ChargeRegularizationShareState.error] (freezed,
/// généré via `build_runner`) porte un champ `message` de type `String` — le
/// régénérer avec un type enum est hors périmètre de cette extraction
/// (nécessite de relancer `build_runner`, non disponible dans cet
/// environnement). Pattern identique à `ReceiptActionError`
/// (`lib/features/receipts/domain/receipt_action_error.dart`) et
/// `TenantSubmitError` (`lib/features/tenants/domain/tenant_submit_error.dart`) :
/// [ChargeRegularizationShareController] stocke le **nom** de cet enum
/// (`ChargeRegularizationShareErrorReason.name`, une clé technique stable,
/// jamais un message FR) dans `ChargeRegularizationShareState.error.message` ;
/// la couche présentation
/// (`charge_regularization_share_error_reason_l10n.dart`) le reconvertit pour
/// l'afficher dans un SnackBar.
///
/// Nommage `...ErrorReason` (pas `...ShareError`) : `ChargeRegularizationShareError`
/// est déjà le nom de la classe générée par freezed pour le variant `error`
/// de `ChargeRegularizationShareState` (voir
/// `charge_regularization_share_state.freezed.dart`) — un enum du même nom
/// entrerait en conflit dès qu'un fichier importe les deux.
enum ChargeRegularizationShareErrorReason {
  /// Échec du partage (Web Share API, réseau, presse-papier) — l'exception
  /// technique d'origine (parfois un DOMException brut, non traduit / non
  /// FR) est loguée par l'appelant mais jamais affichée telle quelle.
  shareFailed,

  /// Erreur générique inattendue (génération PDF, autre).
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans le champ `message` de
  /// l'état d'erreur — retourne [unknown] si absent/invalide (ne doit jamais
  /// arriver en pratique, filet de sécurité défensif).
  static ChargeRegularizationShareErrorReason fromCode(String code) {
    return ChargeRegularizationShareErrorReason.values.firstWhere(
      (e) => e.name == code,
      orElse: () => ChargeRegularizationShareErrorReason.unknown,
    );
  }
}
