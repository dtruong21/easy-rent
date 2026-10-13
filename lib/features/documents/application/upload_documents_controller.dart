import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/plan_matrix.g.dart';
import '../data/documents_repository.dart';
import '../domain/document.dart';
import '../domain/document_category.dart';
import '../domain/upload_documents_state.dart';
import '../domain/upload_file_status.dart';
import 'documents_quota_provider.dart';
import 'lease_documents_provider.dart';

final _log = Logger('UploadDocumentsController');

/// Taille maximale de repli (10 Mo) — utilisée uniquement si le plafond par
/// palier (FEAT-056, `PlanQuota.documentMaxBytes`) n'a pas pu être résolu
/// (provider non encore chargé). La vraie limite, **différenciée par
/// palier** (10 Mio gratuit/Pro, 25 Mio Max, 50 Mio Ultra), vient de la table
/// de droits générée (`plan_matrix.g.dart`) — ne jamais comparer une taille
/// à cette constante directement, passer par `quotaLimitProvider`.
const int kMaxFileSizeBytes = 10 * 1024 * 1024;

/// Nombre maximum de fichiers par batch.
const int kMaxFilesPerBatch = 10;

/// MIME types autorisés côté client (defense in depth — Storage est source de vérité).
const Set<String> kAllowedMimeTypes = {
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
};

/// Fichier sélectionné par le picker, prêt pour l'upload.
class PickedFile {
  const PickedFile({
    required this.filename,
    required this.bytes,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String filename;
  final Uint8List bytes;
  final String mimeType;
  final int sizeBytes;
}

/// Contrôle le flow d'upload multi-fichier.
///
/// État : [UploadDocumentsState]
/// - idle → uploading (per-file pending/uploading/success/error) → completed
///
/// Upload séquentiel (pas parallèle) pour éviter la saturation réseau et les
/// race conditions sur le quota — aligné décision §10 du plan.
class UploadDocumentsController extends StateNotifier<UploadDocumentsState> {
  UploadDocumentsController(this._ref)
    : super(const UploadDocumentsState.idle());

  final Ref _ref;

  /// Lance l'upload batch avec la [defaultCategory] commune à tous les fichiers.
  ///
  /// [pickedFiles] : liste des fichiers sélectionnés par le picker.
  /// [leaseId] : identifiant du bail pour l'INSERT DB et l'invalidation.
  Future<void> uploadFiles({
    required String leaseId,
    required List<PickedFile> pickedFiles,
    required DocumentCategory defaultCategory,
  }) async {
    if (state is! UploadIdle) {
      _log.warning('uploadFiles called while not idle — ignoring');
      return;
    }

    // FEAT-056 : plafond de taille différencié par palier — jamais la
    // constante de repli directement (cf. sa doc).
    final maxFileSizeBytes =
        _ref.read(quotaLimitProvider(PlanQuota.documentMaxBytes)) ??
        kMaxFileSizeBytes;

    // --- Validation préalable ---
    final initial = <UploadFileStatus>[];
    for (final f in pickedFiles) {
      if (f.sizeBytes > maxFileSizeBytes) {
        initial.add(
          UploadFileStatus.error(
            filename: f.filename,
            reason: UploadFileErrorReason.fileTooLarge,
          ),
        );
      } else if (!_isAllowedMime(f.filename, f.mimeType)) {
        initial.add(
          UploadFileStatus.error(
            filename: f.filename,
            reason: UploadFileErrorReason.unsupportedFormat,
          ),
        );
      } else {
        initial.add(
          UploadFileStatus.pending(
            filename: f.filename,
            sizeBytes: f.sizeBytes,
          ),
        );
      }
    }

    state = UploadDocumentsState.uploading(files: List.unmodifiable(initial));

    final repo = _ref.read(documentsRepositoryProvider);
    final current = List<UploadFileStatus>.from(initial);

    // --- Upload séquentiel ---
    for (var i = 0; i < pickedFiles.length; i++) {
      if (current[i] is FileError) continue; // déjà rejeté en prévalide

      final f = pickedFiles[i];
      current[i] = UploadFileStatus.uploading(
        filename: f.filename,
        progress: 0.0,
      );
      state = UploadDocumentsState.uploading(files: List.unmodifiable(current));

      Document? uploaded;
      try {
        uploaded = await repo.upload(
          leaseId: leaseId,
          category: defaultCategory,
          filename: f.filename,
          bytes: f.bytes,
          mimeType: f.mimeType,
          onProgress: (p) {
            current[i] = UploadFileStatus.uploading(
              filename: f.filename,
              progress: p,
            );
            state = UploadDocumentsState.uploading(
              files: List.unmodifiable(current),
            );
          },
        );
        current[i] = UploadFileStatus.success(
          filename: f.filename,
          document: uploaded,
        );
      } on FirebaseFunctionsException catch (e, st) {
        // FEAT-056 : `createDocument` refuse désormais aussi en
        // `resource-exhausted`/`file_too_large` (race avec un plafond client
        // périmé — build ancienne, ou palier rétrogradé entre le pré-check et
        // l'upload). Le serveur fournit `details.limitBytes`/`upgradeTo` :
        // on les propage plutôt que de re-deviner la grille côté client.
        final details = e.details;
        final isFileTooLarge =
            e.code == 'resource-exhausted' &&
            (e.message?.contains('file_too_large') ?? false);
        if (isFileTooLarge) {
          _log.info('server file_too_large uploading ${f.filename}: $details');
          current[i] = UploadFileStatus.error(
            filename: f.filename,
            reason: UploadFileErrorReason.fileTooLarge,
            serverLimitBytes: details is Map
                ? details['limitBytes'] as int?
                : null,
            serverUpgradeToLevelId: details is Map
                ? details['upgradeTo'] as String?
                : null,
          );
        } else {
          _log.warning(
            'FirebaseFunctionsException uploading ${f.filename}',
            e,
            st,
          );
          current[i] = UploadFileStatus.error(
            filename: f.filename,
            reason: UploadFileErrorReason.connectionError,
          );
        }
      } on FirebaseException catch (e, st) {
        _log.warning('FirebaseException uploading ${f.filename}', e, st);
        current[i] = UploadFileStatus.error(
          filename: f.filename,
          reason: e.plugin == 'firebase_storage'
              ? UploadFileErrorReason.storageError
              : UploadFileErrorReason.connectionError,
        );
      } catch (e, st) {
        _log.severe('Erreur inattendue uploading ${f.filename}', e, st);
        current[i] = UploadFileStatus.error(
          filename: f.filename,
          reason: UploadFileErrorReason.unexpected,
        );
      }

      state = UploadDocumentsState.uploading(files: List.unmodifiable(current));
    }

    // --- Résumé ---
    final successCount = current.whereType<FileSuccess>().length;
    final failureCount = current.whereType<FileError>().length;

    state = UploadDocumentsState.completed(
      successCount: successCount,
      failureCount: failureCount,
      files: List.unmodifiable(current),
    );

    if (successCount > 0) {
      _ref.invalidate(leaseDocumentsProvider(leaseId));
      _ref.invalidate(documentsQuotaProvider);
    }

    _log.info(
      'batch upload terminé : $successCount succès, $failureCount échecs',
    );
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const UploadDocumentsState.idle();

  // ---------------------------------------------------------------------------
  // Helpers privés
  // ---------------------------------------------------------------------------

  /// Vérifie si le MIME type est dans la whitelist (defense in depth).
  ///
  /// Utilise le package [mime] pour inférer depuis l'extension si le MIME
  /// fourni est vide ou suspect.
  bool _isAllowedMime(String filename, String providedMime) {
    // Vérification directe du MIME fourni
    if (kAllowedMimeTypes.contains(providedMime)) return true;

    // Fallback : inférer depuis l'extension (package mime)
    final inferred = lookupMimeType(filename);
    return inferred != null && kAllowedMimeTypes.contains(inferred);
  }
}

/// Provider autoDispose du contrôleur d'upload de documents.
///
/// [autoDispose] garantit un state propre entre deux usages de la drop zone.
final uploadDocumentsControllerProvider =
    StateNotifierProvider.autoDispose<
      UploadDocumentsController,
      UploadDocumentsState
    >((ref) => UploadDocumentsController(ref));
