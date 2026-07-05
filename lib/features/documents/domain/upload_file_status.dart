import 'package:freezed_annotation/freezed_annotation.dart';

import 'document.dart';

part 'upload_file_status.freezed.dart';

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

  /// Échec de l'upload — [message] est l'erreur FR à afficher.
  const factory UploadFileStatus.error({
    required String filename,
    required String message,
  }) = FileError;
}
