import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/documents_repository.dart';
import '../domain/document.dart';
import '../domain/document_category.dart';
import 'lease_documents_provider.dart';

final _log = Logger('UpdateDocumentCategoryController');

// ---------------------------------------------------------------------------
// État sealed
// ---------------------------------------------------------------------------

/// Motif d'échec de la mise à jour de catégorie — indépendant de la locale
/// d'affichage (FEAT-043).
///
/// [UpdateDocumentCategoryController] (sans `BuildContext`) reste une
/// fonction pure : il détermine le motif mais ne compose aucun message
/// traduit. La couche présentation ([DocumentListTile]) mappe cet enum vers
/// `context.l10n.<clé>` via l'extension `UpdateCategoryErrorReasonL10n` (voir
/// `lib/features/documents/presentation/update_category_error_reason_l10n.dart`).
enum UpdateCategoryErrorReason {
  /// Erreur réseau/backend (`FirebaseException`) lors de la mise à jour.
  connectionError,

  /// Erreur inattendue non catégorisée.
  unexpected,
}

/// État du flow de mise à jour de catégorie d'un document.
sealed class UpdateCategoryState {
  const UpdateCategoryState();
}

/// Au repos.
final class UpdateCategoryIdle extends UpdateCategoryState {
  const UpdateCategoryIdle();
}

/// Mise à jour en cours.
final class UpdateCategorySubmitting extends UpdateCategoryState {
  const UpdateCategorySubmitting();
}

/// Mise à jour réussie — [document] est le document avec la nouvelle catégorie.
final class UpdateCategorySuccess extends UpdateCategoryState {
  const UpdateCategorySuccess({required this.document});
  final Document document;
}

/// Erreur lors de la mise à jour.
final class UpdateCategoryError extends UpdateCategoryState {
  const UpdateCategoryError({required this.reason});
  final UpdateCategoryErrorReason reason;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Contrôle le flow de mise à jour de la catégorie d'un document.
///
/// Appelle [DocumentsRepository.updateCategory] puis invalide le cache liste.
class UpdateDocumentCategoryController
    extends StateNotifier<UpdateCategoryState> {
  UpdateDocumentCategoryController(this._ref)
    : super(const UpdateCategoryIdle());

  final Ref _ref;

  /// Met à jour la catégorie du document [docId] vers [newCategory].
  ///
  /// [leaseId] : requis pour invalider le cache liste après succès.
  Future<void> update({
    required String docId,
    required DocumentCategory newCategory,
    required String leaseId,
  }) async {
    state = const UpdateCategorySubmitting();

    try {
      final doc = await _ref
          .read(documentsRepositoryProvider)
          .updateCategory(id: docId, newCategory: newCategory);

      _ref.invalidate(leaseDocumentsProvider(leaseId));

      _log.info('category updated id=$docId category=${newCategory.sqlValue}');
      state = UpdateCategorySuccess(document: doc);
    } on FirebaseException catch (e, st) {
      _log.warning('FirebaseException lors de updateCategory', e, st);
      state = const UpdateCategoryError(
        reason: UpdateCategoryErrorReason.connectionError,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de updateCategory', e, st);
      state = const UpdateCategoryError(
        reason: UpdateCategoryErrorReason.unexpected,
      );
    }
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const UpdateCategoryIdle();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider autoDispose.family du contrôleur de mise à jour de catégorie.
///
/// Paramétré par [docId] pour isoler l'état de chaque document.
final updateDocumentCategoryControllerProvider = StateNotifierProvider
    .autoDispose
    .family<UpdateDocumentCategoryController, UpdateCategoryState, String>(
      (ref, docId) => UpdateDocumentCategoryController(ref),
    );
