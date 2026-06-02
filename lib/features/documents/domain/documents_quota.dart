import 'package:freezed_annotation/freezed_annotation.dart';

part 'documents_quota.freezed.dart';

/// Quota de stockage de documents pour le bailleur courant.
///
/// [totalBytes] : somme des `size_bytes` des documents non supprimés.
/// [softLimitBytes] : seuil d'avertissement (100 Mo par défaut).
/// [isOverSoftLimit] : vrai si [totalBytes] >= [softLimitBytes].
@freezed
class DocumentsQuota with _$DocumentsQuota {
  const DocumentsQuota._();

  const factory DocumentsQuota({
    required int totalBytes,
    @Default(104857600) int softLimitBytes, // 100 Mo
  }) = _DocumentsQuota;

  /// Vrai si le bailleur dépasse le seuil d'avertissement.
  bool get isOverSoftLimit => totalBytes >= softLimitBytes;
}
