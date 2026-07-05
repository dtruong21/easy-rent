import 'package:freezed_annotation/freezed_annotation.dart';

part 'expense_receipt_upload_state.freezed.dart';

/// État de l'upload (optionnel) du justificatif d'une dépense.
///
/// Pattern sealed union — cf. [UploadFileStatus] (feature `documents`),
/// simplifié pour un unique fichier (le formulaire dépense n'accepte qu'un
/// seul justificatif, contrairement au batch multi-fichier de la fiche bail).
///
/// Justificatif **recommandé, non bloquant** (décision produit #8,
/// `docs/plans/FEAT-041-depenses.md` § g) — [idle] reste un état de
/// soumission valide.
@freezed
sealed class ExpenseReceiptUploadState with _$ExpenseReceiptUploadState {
  /// Aucun fichier sélectionné — état initial et état final valide (pas de
  /// justificatif joint).
  const factory ExpenseReceiptUploadState.idle() = ReceiptIdle;

  /// Upload en cours — [progress] entre 0.0 et 1.0.
  const factory ExpenseReceiptUploadState.uploading({
    required String filename,
    required double progress,
  }) = ReceiptUploading;

  /// Upload réussi — [documentId] est prêt à être transmis à `createExpense`.
  const factory ExpenseReceiptUploadState.success({
    required String filename,
    required String documentId,
  }) = ReceiptSuccess;

  /// Échec de l'upload — [message] est l'erreur FR à afficher. Le formulaire
  /// reste soumettable (justificatif non bloquant).
  const factory ExpenseReceiptUploadState.error({
    required String filename,
    required String message,
  }) = ReceiptError;

  /// Le bailleur a explicitement retiré le justificatif déjà attaché à la
  /// dépense en édition (`initial.documentId`) — correctif review FEAT-041,
  /// finding 6. Distinct de [idle] : `idle` peut aussi signifier "aucune
  /// interaction pour l'instant, le justificatif existant reste attaché"
  /// (voir `ExpenseReceiptField.existingDocumentId`), alors que [removed]
  /// signifie explicitement "ne plus transmettre ce documentId à la
  /// soumission".
  const factory ExpenseReceiptUploadState.removed() = ReceiptRemoved;
}
