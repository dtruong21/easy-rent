/// Tests unitaires du [UpdateDocumentCategoryController].
library;

import 'dart:typed_data';

import 'package:easyrent/features/documents/application/update_document_category_controller.dart';
import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements DocumentsRepository {
  bool shouldFail = false;

  /// Simule le refus serveur d'un document sous rétention légale
  /// (`FirebaseFunctionsException` avec le code `document_under_legal_hold`).
  bool legalHoldFail = false;
  DocumentCategory? updatedCategory;

  @override
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async {
    if (legalHoldFail) {
      throw FirebaseFunctionsException(
        message: 'document_under_legal_hold',
        code: 'failed-precondition',
      );
    }
    if (shouldFail) throw Exception('update failed');
    updatedCategory = newCategory;
    return Document(
      id: id,
      landlordId: 'l1',
      leaseId: 'lease-1',
      category: newCategory,
      filename: 'test.pdf',
      storagePath: 'prod/l1/documents/$id.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1024,
      legalHold: newCategory.requiresLegalHold,
      uploadedAt: DateTime(2026, 6, 1),
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 2),
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
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async => throw UnimplementedError();

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
  group('UpdateDocumentCategoryController — state initial', () {
    test('commence à idle', () {
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);
      final state = container.read(
        updateDocumentCategoryControllerProvider('doc-1'),
      );
      expect(state, isA<UpdateCategoryIdle>());
    });
  });

  group('UpdateDocumentCategoryController — succès', () {
    test('update → UpdateCategorySuccess avec document mis à jour', () async {
      final repo = _FakeRepo();
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(updateDocumentCategoryControllerProvider('doc-1').notifier)
          .update(
            docId: 'doc-1',
            newCategory: DocumentCategory.bailSigne,
            leaseId: 'lease-1',
          );

      final state = container.read(
        updateDocumentCategoryControllerProvider('doc-1'),
      );
      expect(state, isA<UpdateCategorySuccess>());
      final success = state as UpdateCategorySuccess;
      expect(success.document.category, DocumentCategory.bailSigne);
      expect(repo.updatedCategory, DocumentCategory.bailSigne);
    });
  });

  group('UpdateDocumentCategoryController — erreur', () {
    test('update → UpdateCategoryError si repo lance une exception', () async {
      final repo = _FakeRepo()..shouldFail = true;
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(updateDocumentCategoryControllerProvider('doc-1').notifier)
          .update(
            docId: 'doc-1',
            newCategory: DocumentCategory.bailSigne,
            leaseId: 'lease-1',
          );

      final state = container.read(
        updateDocumentCategoryControllerProvider('doc-1'),
      );
      expect(state, isA<UpdateCategoryError>());
      expect(
        (state as UpdateCategoryError).reason,
        UpdateCategoryErrorReason.unexpected,
      );
    });
  });

  group('UpdateDocumentCategoryController — legalHold', () {
    test(
      'update → UpdateCategoryError(legalHold) si le serveur refuse (rétention)',
      () async {
        final repo = _FakeRepo()..legalHoldFail = true;
        final container = ProviderContainer(
          overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await container
            .read(updateDocumentCategoryControllerProvider('doc-1').notifier)
            .update(
              docId: 'doc-1',
              newCategory: DocumentCategory.autre,
              leaseId: 'lease-1',
            );

        final state = container.read(
          updateDocumentCategoryControllerProvider('doc-1'),
        );
        expect(state, isA<UpdateCategoryError>());
        expect(
          (state as UpdateCategoryError).reason,
          UpdateCategoryErrorReason.legalHold,
        );
      },
    );
  });

  group('UpdateDocumentCategoryController.reset', () {
    test('reset → idle', () async {
      final repo = _FakeRepo();
      final container = ProviderContainer(
        overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(updateDocumentCategoryControllerProvider('doc-1').notifier)
          .update(
            docId: 'doc-1',
            newCategory: DocumentCategory.autre,
            leaseId: 'lease-1',
          );

      container
          .read(updateDocumentCategoryControllerProvider('doc-1').notifier)
          .reset();

      final state = container.read(
        updateDocumentCategoryControllerProvider('doc-1'),
      );
      expect(state, isA<UpdateCategoryIdle>());
    });
  });
}
