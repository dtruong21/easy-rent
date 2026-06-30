import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/documents_repository.dart';
import 'documents_quota_provider.dart';
import 'lease_documents_provider.dart';

final _log = Logger('DeleteDocumentController');

// ---------------------------------------------------------------------------
// État sealed
// ---------------------------------------------------------------------------

/// État du flow de suppression d'un document.
sealed class DeleteDocumentState {
  const DeleteDocumentState();
}

/// Au repos — prêt à recevoir une action.
final class DeleteIdle extends DeleteDocumentState {
  const DeleteIdle();
}

/// Suppression en cours.
final class DeleteSubmitting extends DeleteDocumentState {
  const DeleteSubmitting();
}

/// Suppression réussie.
///
/// [hardDeleted] : vrai si le fichier a aussi été supprimé du Storage.
/// False si le document est sous legal_hold (fichier conservé en Storage).
final class DeleteSuccess extends DeleteDocumentState {
  const DeleteSuccess({required this.hardDeleted});
  final bool hardDeleted;
}

/// Erreur lors de la suppression.
final class DeleteError extends DeleteDocumentState {
  const DeleteError({required this.message});
  final String message;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Contrôle le flow de suppression (soft-delete) d'un document.
///
/// Appelle la RPC `soft_delete_document` via [DocumentsRepository.softDelete].
/// Sur succès : invalide [leaseDocumentsProvider(leaseId)] et [documentsQuotaProvider].
class DeleteDocumentController extends StateNotifier<DeleteDocumentState> {
  DeleteDocumentController(this._ref) : super(const DeleteIdle());

  final Ref _ref;

  /// Effectue le soft-delete du document [docId].
  ///
  /// [leaseId] : requis pour invalider le cache liste après succès.
  Future<void> delete({required String docId, required String leaseId}) async {
    state = const DeleteSubmitting();

    try {
      final result = await _ref
          .read(documentsRepositoryProvider)
          .softDelete(docId);

      _ref.invalidate(leaseDocumentsProvider(leaseId));
      _ref.invalidate(documentsQuotaProvider);

      _log.info('document deleted id=$docId hardDeleted=${result.hardDeleted}');
      state = DeleteSuccess(hardDeleted: result.hardDeleted);
    } on FirebaseException catch (e, st) {
      _log.warning('FirebaseException lors du soft-delete', e, st);
      state = DeleteError(
        message: "Erreur. Vérifiez votre connexion et réessayez.",
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors du soft-delete', e, st);
      state = const DeleteError(message: 'Suppression impossible. Réessayez.');
    }
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const DeleteIdle();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider autoDispose.family du contrôleur de suppression.
///
/// Paramétré par [docId] pour isoler l'état de chaque document.
final deleteDocumentControllerProvider = StateNotifierProvider.autoDispose
    .family<DeleteDocumentController, DeleteDocumentState, String>(
      (ref, docId) => DeleteDocumentController(ref),
    );
