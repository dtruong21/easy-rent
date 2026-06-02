import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/postgrest_error_mapper.dart';
import '../data/documents_repository.dart';
import '../domain/document.dart';
import '../domain/document_category.dart';
import 'lease_documents_provider.dart';

final _log = Logger('UpdateDocumentCategoryController');

// ---------------------------------------------------------------------------
// État sealed
// ---------------------------------------------------------------------------

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
  const UpdateCategoryError({required this.message});
  final String message;
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
    } on PostgrestException catch (e, st) {
      _log.warning('PostgrestException lors de updateCategory', e, st);
      state = UpdateCategoryError(message: mapPostgrestError(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de updateCategory', e, st);
      state = const UpdateCategoryError(
        message: 'Modification impossible. Réessayez.',
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
