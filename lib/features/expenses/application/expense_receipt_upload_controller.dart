import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import '../../documents/application/upload_documents_controller.dart'
    show kAllowedMimeTypes, kMaxFileSizeBytes;
import '../../documents/data/documents_repository.dart';
import '../../documents/domain/document_category.dart';
import '../domain/expense_receipt_upload_state.dart';

final _log = Logger('ExpenseReceiptUploadController');

/// Contrôle l'upload optionnel d'un justificatif de dépense
/// (`DocumentCategory.expenseReceipt`).
///
/// Justificatif **recommandé, non bloquant** (décision produit #8) : le
/// formulaire de dépense reste soumettable même si aucun fichier n'est joint,
/// ou si l'upload échoue — l'utilisateur peut simplement retirer/réessayer.
///
/// Réutilise [DocumentsRepository.upload] (pipeline Storage → Callable
/// `createDocument` v2) — voir `docs/plans/FEAT-041-depenses.md` § g).
class ExpenseReceiptUploadController
    extends StateNotifier<ExpenseReceiptUploadState> {
  ExpenseReceiptUploadController(this._ref)
    : super(const ExpenseReceiptUploadState.idle());

  final Ref _ref;

  /// Lance l'upload du justificatif pour le bien/bail courant.
  ///
  /// Au moins un des deux (`propertyId`/`leaseId`) est requis — cohérent
  /// avec `createDocument` v2. Sur succès, [documentId] est exposé via
  /// l'état [ExpenseReceiptUploadState.success].
  Future<void> upload({
    required String propertyId,
    String? leaseId,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (bytes.length > kMaxFileSizeBytes) {
      state = ExpenseReceiptUploadState.error(
        filename: filename,
        message: 'Le fichier dépasse 10 Mo.',
      );
      return;
    }
    if (!_isAllowedMime(filename, mimeType)) {
      state = ExpenseReceiptUploadState.error(
        filename: filename,
        message: 'Format non supporté. Formats acceptés : PDF, JPG, PNG, WEBP.',
      );
      return;
    }

    state = ExpenseReceiptUploadState.uploading(
      filename: filename,
      progress: 0.0,
    );

    try {
      final repo = _ref.read(documentsRepositoryProvider);
      final document = await repo.upload(
        leaseId: leaseId,
        propertyId: propertyId,
        category: DocumentCategory.expenseReceipt,
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
        onProgress: (p) {
          state = ExpenseReceiptUploadState.uploading(
            filename: filename,
            progress: p,
          );
        },
      );
      _log.info('receipt uploaded documentId=${document.id}');
      state = ExpenseReceiptUploadState.success(
        filename: filename,
        documentId: document.id,
      );
    } on FirebaseException catch (e, st) {
      _log.warning('FirebaseException uploading receipt $filename', e, st);
      state = ExpenseReceiptUploadState.error(
        filename: filename,
        message: e.plugin == 'firebase_storage'
            ? "Erreur lors de l'upload. Réessayez."
            : 'Erreur. Vérifiez votre connexion et réessayez.',
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue uploading receipt $filename', e, st);
      state = ExpenseReceiptUploadState.error(
        filename: filename,
        message: "Erreur lors de l'envoi. Réessayez.",
      );
    }
  }

  /// Retire le justificatif sélectionné/uploadé — remet l'état à idle.
  ///
  /// Ne supprime pas le document déjà créé côté serveur (protégé par
  /// `legalHold` — nettoyage cron identifié P2, cf. plan § g). Le formulaire
  /// simplement n'envoie plus ce `documentId` à `createExpense`.
  void reset() => state = const ExpenseReceiptUploadState.idle();

  bool _isAllowedMime(String filename, String providedMime) {
    if (kAllowedMimeTypes.contains(providedMime)) return true;
    final inferred = lookupMimeType(filename);
    return inferred != null && kAllowedMimeTypes.contains(inferred);
  }
}

/// Provider autoDispose du contrôleur d'upload de justificatif.
///
/// [autoDispose] garantit un état propre entre deux ouvertures du formulaire
/// dépense.
final expenseReceiptUploadControllerProvider =
    StateNotifierProvider.autoDispose<
      ExpenseReceiptUploadController,
      ExpenseReceiptUploadState
    >((ref) => ExpenseReceiptUploadController(ref));
