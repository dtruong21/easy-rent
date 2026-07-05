import 'package:freezed_annotation/freezed_annotation.dart';

import 'upload_file_status.dart';

part 'upload_documents_state.freezed.dart';

/// État global du flow d'upload multi-fichier.
///
/// - [idle] : aucun upload en cours.
/// - [uploading] : batch en cours — [files] suit l'état de chaque fichier.
/// - [completed] : tous les fichiers ont été traités (succès ou échec).
@freezed
sealed class UploadDocumentsState with _$UploadDocumentsState {
  /// Au repos — prêt à recevoir un batch.
  const factory UploadDocumentsState.idle() = UploadIdle;

  /// Upload en cours — [files] liste l'état de chaque fichier dans l'ordre.
  const factory UploadDocumentsState.uploading({
    required List<UploadFileStatus> files,
  }) = Uploading;

  /// Tous les fichiers ont été traités.
  ///
  /// [successCount] : nombre de fichiers uploadés avec succès.
  /// [failureCount] : nombre de fichiers en erreur.
  /// [files] : détail par fichier pour affichage récap.
  const factory UploadDocumentsState.completed({
    required int successCount,
    required int failureCount,
    required List<UploadFileStatus> files,
  }) = UploadCompleted;
}
