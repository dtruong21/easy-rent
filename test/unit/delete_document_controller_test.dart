/// Tests unitaires du [DeleteDocumentController].
library;

import 'dart:typed_data';

import 'package:easyrent/features/documents/application/delete_document_controller.dart';
import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements DocumentsRepository {
  bool shouldFail = false;
  bool hardDeleteResult = true;
  bool legalHoldResult = false;

  @override
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async {
    if (shouldFail) throw Exception('soft delete failed');
    if (legalHoldResult) {
      return (storagePath: null, hardDeleted: false);
    }
    return (
      storagePath: 'prod/landlord-1/documents/$id.pdf',
      hardDeleted: hardDeleteResult,
    );
  }

  @override
  Future<List<Document>> listForLease(String leaseId) async => [];

  @override
  Future<Document> getById(String id) async => throw UnimplementedError();

  @override
  Future<Document> upload({
    String? leaseId,
    String? propertyId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async => throw UnimplementedError();

  @override
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async => throw UnimplementedError();

  @override
  Future<String> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 300,
  }) async => throw UnimplementedError();

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async =>
      const DocumentsQuota(totalBytes: 0);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DeleteDocumentController — state initial', () {
    test('commence à idle', () {
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);
      final state = container.read(deleteDocumentControllerProvider('doc-1'));
      expect(state, isA<DeleteIdle>());
    });
  });

  group('DeleteDocumentController — succès sans legal_hold', () {
    test('delete → DeleteSuccess(hardDeleted=true)', () async {
      final repo = _FakeRepo()..hardDeleteResult = true;
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(deleteDocumentControllerProvider('doc-1').notifier)
          .delete(docId: 'doc-1', leaseId: 'lease-1');

      final state = container.read(deleteDocumentControllerProvider('doc-1'));
      expect(state, isA<DeleteSuccess>());
      expect((state as DeleteSuccess).hardDeleted, true);
    });
  });

  group('DeleteDocumentController — succès avec legal_hold', () {
    test('delete → DeleteSuccess(hardDeleted=false)', () async {
      final repo = _FakeRepo()..legalHoldResult = true;
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(deleteDocumentControllerProvider('doc-1').notifier)
          .delete(docId: 'doc-1', leaseId: 'lease-1');

      final state = container.read(deleteDocumentControllerProvider('doc-1'));
      expect(state, isA<DeleteSuccess>());
      expect((state as DeleteSuccess).hardDeleted, false);
    });
  });

  group('DeleteDocumentController — erreur', () {
    test('delete → DeleteError si repo lance une exception', () async {
      final repo = _FakeRepo()..shouldFail = true;
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(deleteDocumentControllerProvider('doc-1').notifier)
          .delete(docId: 'doc-1', leaseId: 'lease-1');

      final state = container.read(deleteDocumentControllerProvider('doc-1'));
      expect(state, isA<DeleteError>());
      expect(
        (state as DeleteError).reason,
        DeleteDocumentErrorReason.unexpected,
      );
    });
  });

  group('DeleteDocumentController.reset', () {
    test('reset → idle', () async {
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await container
          .read(deleteDocumentControllerProvider('doc-1').notifier)
          .delete(docId: 'doc-1', leaseId: 'lease-1');

      container
          .read(deleteDocumentControllerProvider('doc-1').notifier)
          .reset();

      final state = container.read(deleteDocumentControllerProvider('doc-1'));
      expect(state, isA<DeleteIdle>());
    });
  });
}
