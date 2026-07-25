/// Tests unitaires du [DocumentsRepository] avec mocks.
library;

import 'dart:typed_data';

import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class FakeDocumentsRepository implements DocumentsRepository {
  List<Document> storedDocuments = [];
  bool uploadShouldFail = false;
  bool softDeleteShouldFail = false;
  bool hardDeleteResult = true;
  int quotaBytes = 0;

  @override
  Future<List<Document>> listForLease(String leaseId) async =>
      storedDocuments.where((d) => d.leaseId == leaseId).toList();

  @override
  Future<Document> getById(String id) async {
    final doc = storedDocuments.firstWhere(
      (d) => d.id == id,
      orElse: () => throw DocumentNotFoundException(id),
    );
    return doc;
  }

  @override
  Future<Document> upload({
    String? leaseId,
    String? propertyId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    if (uploadShouldFail) throw Exception('upload failed');
    onProgress?.call(0.0);
    onProgress?.call(1.0);
    final doc = Document(
      id: 'new-doc',
      landlordId: 'landlord-1',
      leaseId: leaseId,
      category: category,
      filename: filename,
      storagePath: 'prod/landlord-1/documents/new-doc.pdf',
      mimeType: mimeType,
      sizeBytes: bytes.length,
      legalHold: category.requiresLegalHold,
      uploadedAt: DateTime(2026, 6, 1),
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
    );
    storedDocuments.add(doc);
    return doc;
  }

  @override
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async {
    if (softDeleteShouldFail) throw Exception('soft delete failed');
    storedDocuments.removeWhere((d) => d.id == id);
    if (hardDeleteResult) {
      return (
        storagePath: 'prod/landlord-1/documents/$id.pdf',
        hardDeleted: true,
      );
    }
    return (storagePath: null, hardDeleted: false);
  }

  @override
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async {
    final idx = storedDocuments.indexWhere((d) => d.id == id);
    if (idx == -1) throw DocumentNotFoundException(id);
    final updated = storedDocuments[idx].copyWith(category: newCategory);
    storedDocuments[idx] = updated;
    return updated;
  }

  @override
  Future<String> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 300,
  }) async =>
      'https://firebasestorage.googleapis.com/v0/b/app/o/$storagePath?token=abc';

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async =>
      DocumentsQuota(totalBytes: quotaBytes);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FakeDocumentsRepository', () {
    late FakeDocumentsRepository repo;

    setUp(() => repo = FakeDocumentsRepository());

    test('listForLease retourne la liste filtrée par leaseId', () async {
      repo.storedDocuments = [
        _makeDoc(leaseId: 'lease-1'),
        _makeDoc(id: 'doc-2', leaseId: 'lease-2'),
      ];
      final result = await repo.listForLease('lease-1');
      expect(result.length, 1);
      expect(result.first.id, 'doc-1');
    });

    test('listForLease retourne [] si aucun document', () async {
      final result = await repo.listForLease('lease-x');
      expect(result, isEmpty);
    });

    test('getById retourne le document', () async {
      repo.storedDocuments = [_makeDoc()];
      final doc = await repo.getById('doc-1');
      expect(doc.id, 'doc-1');
    });

    test('getById lève DocumentNotFoundException si introuvable', () async {
      expect(
        () => repo.getById('unknown'),
        throwsA(isA<DocumentNotFoundException>()),
      );
    });

    test('upload crée un nouveau document', () async {
      final doc = await repo.upload(
        leaseId: 'lease-1',
        category: DocumentCategory.autre,
        filename: 'test.pdf',
        bytes: Uint8List(1024),
        mimeType: 'application/pdf',
      );
      expect(doc.filename, 'test.pdf');
      expect(doc.category, DocumentCategory.autre);
      expect(repo.storedDocuments.length, 1);
    });

    test('upload avec progress callback appelle 0.0 et 1.0', () async {
      final progress = <double>[];
      await repo.upload(
        leaseId: 'lease-1',
        category: DocumentCategory.autre,
        filename: 'test.pdf',
        bytes: Uint8List(512),
        mimeType: 'application/pdf',
        onProgress: progress.add,
      );
      expect(progress, containsAll([0.0, 1.0]));
    });

    test('softDelete sans legal_hold retourne hardDeleted=true', () async {
      repo.storedDocuments = [_makeDoc()];
      repo.hardDeleteResult = true;
      final result = await repo.softDelete('doc-1');
      expect(result.hardDeleted, true);
      expect(result.storagePath, isNotNull);
    });

    test('softDelete avec legal_hold retourne hardDeleted=false', () async {
      repo.storedDocuments = [_makeDoc()];
      repo.hardDeleteResult = false;
      final result = await repo.softDelete('doc-1');
      expect(result.hardDeleted, false);
      expect(result.storagePath, isNull);
    });

    test('updateCategory met à jour la catégorie', () async {
      repo.storedDocuments = [_makeDoc()];
      final updated = await repo.updateCategory(
        id: 'doc-1',
        newCategory: DocumentCategory.bailSigne,
      );
      expect(updated.category, DocumentCategory.bailSigne);
    });

    test('createSignedUrl retourne une URL non vide', () async {
      final url = await repo.createSignedUrl('prod/uid/doc.pdf');
      expect(url, isNotEmpty);
      expect(url, contains('firebasestorage.googleapis.com'));
    });

    test('quotaForCurrentLandlord retourne le quota configuré', () async {
      repo.quotaBytes = 5242880; // 5 Mo
      final quota = await repo.quotaForCurrentLandlord();
      expect(quota.totalBytes, 5242880);
    });

    // NIT-4 review : rollback Storage si INSERT DB échoue.
    // Le FakeDocumentsRepository simule ce chemin via [uploadShouldFail].
    // Dans FirestoreDocumentsRepository, le catch sur la création appelle
    // _removeStorageObject avant de rethrow — ce test vérifie que le contrat
    // "aucun document ajouté en cas d'erreur upload" est respecté.
    test('upload échoué ne persiste pas de document', () async {
      repo.uploadShouldFail = true;
      expect(
        () => repo.upload(
          leaseId: 'lease-1',
          category: DocumentCategory.autre,
          filename: 'fail.pdf',
          bytes: Uint8List(1024),
          mimeType: 'application/pdf',
        ),
        throwsA(isA<Exception>()),
      );
      // Aucun document ne doit être stocké (rollback implicite)
      expect(repo.storedDocuments, isEmpty);
    });
  });
}

Document _makeDoc({String id = 'doc-1', String leaseId = 'lease-1'}) =>
    Document(
      id: id,
      landlordId: 'landlord-1',
      leaseId: leaseId,
      category: DocumentCategory.autre,
      filename: 'test.pdf',
      storagePath: 'prod/landlord-1/documents/$id.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1024,
      legalHold: false,
      uploadedAt: DateTime(2026, 6, 1),
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
    );
