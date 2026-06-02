/// Tests du modèle [Document] — freezed, JSON round-trip, extensions.
library;

import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Document _makeDoc({
  String id = 'doc-1',
  DocumentCategory category = DocumentCategory.autre,
  String filename = 'contrat.pdf',
  String mimeType = 'application/pdf',
  int sizeBytes = 1048576, // 1 Mo
  bool legalHold = false,
}) => Document(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  category: category,
  filename: filename,
  storagePath: 'prod/landlord-1/documents/$id.pdf',
  mimeType: mimeType,
  sizeBytes: sizeBytes,
  legalHold: legalHold,
  uploadedAt: DateTime(2026, 6, 1),
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

Map<String, dynamic> _makeJson({
  String id = 'doc-1',
  String category = 'autre',
  String mimeType = 'application/pdf',
  int sizeBytes = 1048576,
  bool legalHold = false,
}) => {
  'id': id,
  'landlord_id': 'landlord-1',
  'lease_id': 'lease-1',
  'category': category,
  'filename': 'contrat.pdf',
  'storage_path': 'prod/landlord-1/documents/$id.pdf',
  'mime_type': mimeType,
  'size_bytes': sizeBytes,
  'legal_hold': legalHold,
  'uploaded_at': '2026-06-01T00:00:00.000Z',
  'created_at': '2026-06-01T00:00:00.000Z',
  'updated_at': '2026-06-01T00:00:00.000Z',
  'deleted_at': null,
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Document.fromJson', () {
    test('désérialise correctement un JSON valide', () {
      final doc = Document.fromJson(_makeJson());
      expect(doc.id, 'doc-1');
      expect(doc.landlordId, 'landlord-1');
      expect(doc.leaseId, 'lease-1');
      expect(doc.category, DocumentCategory.autre);
      expect(doc.filename, 'contrat.pdf');
      expect(doc.mimeType, 'application/pdf');
      expect(doc.sizeBytes, 1048576);
      expect(doc.legalHold, false);
      expect(doc.deletedAt, isNull);
    });

    test('désérialise category bail_signe', () {
      final doc = Document.fromJson(_makeJson(category: 'bail_signe'));
      expect(doc.category, DocumentCategory.bailSigne);
    });

    test('désérialise legalHold = true', () {
      final doc = Document.fromJson(_makeJson(legalHold: true));
      expect(doc.legalHold, true);
    });

    test('désérialise mime_type image/jpeg', () {
      final doc = Document.fromJson(_makeJson(mimeType: 'image/jpeg'));
      expect(doc.mimeType, 'image/jpeg');
    });
  });

  group('Document.toJson', () {
    test('sérialise correctement en JSON', () {
      final doc = _makeDoc();
      final json = doc.toJson();
      expect(json['id'], 'doc-1');
      expect(json['landlord_id'], 'landlord-1');
      expect(json['category'], 'autre');
      expect(json['mime_type'], 'application/pdf');
      expect(json['legal_hold'], false);
    });
  });

  group('Document JSON round-trip', () {
    test('fromJson → toJson → fromJson est idempotent', () {
      final original = _makeDoc();
      final json = original.toJson();
      final restored = Document.fromJson(json);
      expect(restored, original);
    });

    test('round-trip avec category bail_signe', () {
      final original = _makeDoc(category: DocumentCategory.bailSigne);
      final restored = Document.fromJson(original.toJson());
      expect(restored.category, DocumentCategory.bailSigne);
    });
  });

  group('DocumentX.sizeHuman', () {
    test('affiche en octets pour < 1024', () {
      final doc = _makeDoc(sizeBytes: 512);
      expect(doc.sizeHuman, '512 o');
    });

    test('affiche en Ko pour 1024..1048575', () {
      final doc = _makeDoc(sizeBytes: 870400);
      expect(doc.sizeHuman, contains('Ko'));
    });

    test('affiche en Mo pour >= 1048576', () {
      final doc = _makeDoc(sizeBytes: 1048576);
      expect(doc.sizeHuman, contains('Mo'));
    });

    test('1 Mo formaté avec séparateur FR', () {
      final doc = _makeDoc(sizeBytes: 1048576);
      // 1 Mo exact
      expect(doc.sizeHuman, '1 Mo');
    });

    test('2.4 Mo formaté avec virgule FR', () {
      final doc = _makeDoc(sizeBytes: 2516582);
      expect(doc.sizeHuman, contains(','));
      expect(doc.sizeHuman, contains('Mo'));
    });
  });

  group('DocumentX.isImage / isPdf', () {
    test('isPdf vrai pour application/pdf', () {
      final doc = _makeDoc(mimeType: 'application/pdf');
      expect(doc.isPdf, true);
      expect(doc.isImage, false);
    });

    test('isImage vrai pour image/jpeg', () {
      final doc = _makeDoc(mimeType: 'image/jpeg');
      expect(doc.isImage, true);
      expect(doc.isPdf, false);
    });

    test('isImage vrai pour image/png', () {
      final doc = _makeDoc(mimeType: 'image/png');
      expect(doc.isImage, true);
    });

    test('isImage vrai pour image/webp', () {
      final doc = _makeDoc(mimeType: 'image/webp');
      expect(doc.isImage, true);
    });
  });

  group('DocumentX.extension', () {
    test('extension pdf', () {
      final doc = _makeDoc(filename: 'contrat.pdf');
      expect(doc.extension, 'pdf');
    });

    test('extension jpg', () {
      final doc = _makeDoc(filename: 'photo.jpg');
      expect(doc.extension, 'jpg');
    });

    test('extension vide si pas de point', () {
      final doc = _makeDoc(filename: 'sans_extension');
      expect(doc.extension, '');
    });
  });

  group('DocumentX.uploadedAtLabel', () {
    test('format FR JJ/MM/AAAA', () {
      final doc = _makeDoc();
      expect(doc.uploadedAtLabel, '01/06/2026');
    });
  });

  group('Document.copyWith', () {
    test('copyWith modifie category', () {
      final doc = _makeDoc();
      final updated = doc.copyWith(category: DocumentCategory.bailSigne);
      expect(updated.category, DocumentCategory.bailSigne);
      expect(updated.id, doc.id);
    });
  });
}
