/// Motif d'échec de l'upload du justificatif d'une dépense, indépendant de
/// la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : `ExpenseReceiptUploadState.error` (freezed,
/// généré via `build_runner`) porte un champ `message` de type `String` — le
/// régénérer avec un type enum est hors périmètre de cette extraction
/// (nécessite de relancer `build_runner`, non disponible dans cet
/// environnement). Pattern retenu, identique à `ExpenseSubmitError`
/// (`lib/features/expenses/domain/expense_submit_error.dart`) :
/// [ExpenseReceiptUploadController]
/// (`lib/features/expenses/application/expense_receipt_upload_controller.dart`)
/// stocke le **nom** de cet enum
/// (`ExpenseReceiptUploadErrorReason.name`, une clé technique stable, jamais
/// un message FR) dans `ExpenseReceiptUploadState.error.message` ; la couche
/// présentation (`expense_receipt_upload_error_reason_l10n.dart`) le
/// reconvertit via [ExpenseReceiptUploadErrorReasonL10n] pour l'afficher.
///
/// Mêmes motifs que `UploadFileErrorReason`
/// (`lib/features/documents/domain/upload_file_status.dart`) — dupliqués ici
/// plutôt que réutilisés pour ne pas introduire de dépendance croisée
/// `expenses` → `documents` au niveau domaine (seule la couche `application`
/// réutilise déjà le pipeline d'upload sous-jacent, cf.
/// `ExpenseReceiptUploadController`). Les clés ARB résultantes
/// (`expensesReceiptError*`) sont donc de proches doublons de
/// `documentsUpload*`/`documentsErrorConnection` — dédup identifiée comme
/// suivi possible (même remarque que le suivi de dédup FEAT-043 vague 3).
enum ExpenseReceiptUploadErrorReason {
  /// Fichier > 10 Mo (validation cliente pré-upload, `kMaxFileSizeBytes`).
  fileTooLarge,

  /// MIME type hors whitelist (validation cliente pré-upload,
  /// `kAllowedMimeTypes`).
  unsupportedFormat,

  /// Erreur Firebase Storage lors de l'upload du fichier (`e.plugin ==
  /// 'firebase_storage'`).
  storageError,

  /// Erreur réseau/backend générique (Firestore/Callable `createDocument`).
  connectionError,

  /// Erreur inattendue non catégorisée.
  unexpected;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `ExpenseReceiptUploadState.error.message` — retourne [unexpected] si
  /// absent/invalide (ne doit jamais arriver en pratique, filet de sécurité
  /// défensif).
  static ExpenseReceiptUploadErrorReason fromCode(String code) {
    return ExpenseReceiptUploadErrorReason.values.firstWhere(
      (e) => e.name == code,
      orElse: () => ExpenseReceiptUploadErrorReason.unexpected,
    );
  }
}
