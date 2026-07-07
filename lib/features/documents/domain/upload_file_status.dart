import 'package:freezed_annotation/freezed_annotation.dart';

import 'document.dart';

part 'upload_file_status.freezed.dart';

/// Motif d'échec de l'upload d'un fichier — indépendant de la locale
/// d'affichage (FEAT-043).
///
/// [UploadDocumentsController] (application, sans `BuildContext`) reste une
/// fonction pure : il détermine le motif mais ne compose aucun message
/// traduit. La couche présentation ([UploadProgressList]) mappe cet enum vers
/// `context.l10n.<clé>` via l'extension `UploadFileErrorReasonL10n` (voir
/// `lib/features/documents/presentation/upload_file_error_reason_l10n.dart`).
enum UploadFileErrorReason {
  /// Fichier > 10 Mo (validation cliente pré-upload, [kMaxFileSizeBytes]).
  fileTooLarge,

  /// MIME type hors whitelist (validation cliente pré-upload,
  /// [kAllowedMimeTypes]).
  unsupportedFormat,

  /// Erreur Firebase Storage lors de l'upload du fichier (`e.plugin ==
  /// 'firebase_storage'`).
  storageError,

  /// Erreur réseau/backend générique (Firestore/Callable `createDocument`).
  connectionError,

  /// Erreur inattendue non catégorisée.
  unexpected,
}

/// Statut d'un fichier individuel lors d'un batch d'upload.
///
/// Pattern sealed union — chaque variant représente un état distinct.
@freezed
sealed class UploadFileStatus with _$UploadFileStatus {
  /// Fichier en attente d'upload.
  const factory UploadFileStatus.pending({
    required String filename,
    required int sizeBytes,
  }) = FilePending;

  /// Upload en cours — [progress] entre 0.0 et 1.0.
  const factory UploadFileStatus.uploading({
    required String filename,
    required double progress,
  }) = FileUploading;

  /// Upload réussi — [document] est le document créé.
  const factory UploadFileStatus.success({
    required String filename,
    required Document document,
  }) = FileSuccess;

  /// Échec de l'upload — [reason] est traduit en présentation (voir
  /// [UploadFileErrorReason]).
  const factory UploadFileStatus.error({
    required String filename,
    required UploadFileErrorReason reason,
  }) = FileError;
}
