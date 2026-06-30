import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../data/documents_repository.dart';
import '../domain/document.dart';
import '../domain/document_category.dart';
import '../domain/upload_documents_state.dart';
import '../domain/upload_file_status.dart';
import 'documents_quota_provider.dart';
import 'lease_documents_provider.dart';

final _log = Logger('UploadDocumentsController');

/// Taille maximale autorisée par fichier (10 Mo).
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

    // --- Validation préalable ---
    final initial = <UploadFileStatus>[];
    for (final f in pickedFiles) {
      if (f.sizeBytes > kMaxFileSizeBytes) {
        initial.add(
          UploadFileStatus.error(
            filename: f.filename,
            message: 'Le fichier dépasse 10 Mo.',
          ),
        );
      } else if (!_isAllowedMime(f.filename, f.mimeType)) {
        initial.add(
          UploadFileStatus.error(
            filename: f.filename,
            message:
                'Format non supporté. Formats acceptés : PDF, JPG, PNG, WEBP.',
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
      } on FirebaseException catch (e, st) {
        _log.warning('FirebaseException uploading ${f.filename}', e, st);
        current[i] = UploadFileStatus.error(
          filename: f.filename,
          message: e.plugin == 'firebase_storage'
              ? "Erreur lors de l'upload. Réessayez."
              : 'Erreur. Vérifiez votre connexion et réessayez.',
        );
      } catch (e, st) {
        _log.severe('Erreur inattendue uploading ${f.filename}', e, st);
        current[i] = UploadFileStatus.error(
          filename: f.filename,
          message: 'Erreur lors de l\'envoi. Réessayez.',
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
