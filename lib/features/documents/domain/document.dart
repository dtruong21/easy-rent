// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/byte_format.dart';
import '../../../core/utils/french_date.dart';
import 'document_category.dart';

part 'document.freezed.dart';
part 'document.g.dart';

/// Modèle immutable d'un document attaché à un bail.
///
/// Mappé directement sur la table `documents` (public + dev).
/// Seul [category] est UPDATE-able après création (trigger `tr_01b_protect_immutable_documents`).
/// La suppression se fait uniquement via RPC `soft_delete_document`.
@freezed
class Document with _$Document {
  const factory Document({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'lease_id') required String leaseId,
    @JsonKey(fromJson: _categoryFromJson, toJson: _categoryToJson)
    required DocumentCategory category,
    required String filename,
    @JsonKey(name: 'storage_path') required String storagePath,
    @JsonKey(name: 'mime_type') required String mimeType,
    @JsonKey(name: 'size_bytes') required int sizeBytes,
    @JsonKey(name: 'legal_hold') required bool legalHold,
    @JsonKey(name: 'uploaded_at') required DateTime uploadedAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Document;

  factory Document.fromJson(Map<String, dynamic> json) =>
      _$DocumentFromJson(json);
}

// ---------------------------------------------------------------------------
// Helpers JSON privés
// ---------------------------------------------------------------------------

DocumentCategory _categoryFromJson(dynamic value) =>
    DocumentCategory.fromSql(value as String);

String _categoryToJson(DocumentCategory cat) => cat.sqlValue;

// ---------------------------------------------------------------------------
// Extension — getters calculés
// ---------------------------------------------------------------------------

/// Getters utilitaires sur un document.
extension DocumentX on Document {
  /// Taille formatée en FR : "2,4 Mo", "850 Ko", "512 o".
  String get sizeHuman => ByteFormat.format(sizeBytes);

  /// Date d'upload formatée en FR : "01/06/2026".
  String get uploadedAtLabel => FrenchDate.format(uploadedAt);

  /// Extension de fichier (sans le point), en minuscules.
  String get extension {
    final parts = filename.split('.');
    if (parts.length <= 1) return '';
    return parts.last.toLowerCase();
  }

  /// Vrai si le document est une image (JPEG, PNG, WEBP).
  bool get isImage => mimeType.startsWith('image/');

  /// Vrai si le document est un PDF.
  bool get isPdf => mimeType == 'application/pdf';
}
