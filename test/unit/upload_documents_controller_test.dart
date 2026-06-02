/// Tests unitaires du [UploadDocumentsController].
library;

import 'dart:typed_data';

import 'package:easyrent/features/documents/application/upload_documents_controller.dart';
import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:easyrent/features/documents/domain/upload_documents_state.dart';
import 'package:easyrent/features/documents/domain/upload_file_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements DocumentsRepository {
  bool shouldFail = false;
  int uploadCallCount = 0;

  @override
  Future<Document> upload({
    required String leaseId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    uploadCallCount++;
    if (shouldFail) throw Exception('upload failed');
    return Document(
      id: 'doc-$uploadCallCount',
      landlordId: 'l1',
      leaseId: leaseId,
      category: category,
      filename: filename,
      storagePath: 'prod/l1/documents/doc-$uploadCallCount.pdf',
      mimeType: mimeType,
      sizeBytes: bytes.length,
      legalHold: false,
      uploadedAt: DateTime(2026, 6, 1),
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
    );
  }

  @override
  Future<List<Document>> listForLease(String leaseId) async => [];

  @override
  Future<Document> getById(String id) async => throw UnimplementedError();

  @override
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async => throw UnimplementedError();

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
// Helper
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(_FakeRepo repo) {
  return ProviderContainer(
    overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
  );
}

PickedFile _file({
  String name = 'test.pdf',
  String mime = 'application/pdf',
  int size = 1024,
}) => PickedFile(
  filename: name,
  bytes: Uint8List(size),
  mimeType: mime,
  sizeBytes: size,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UploadDocumentsController — état initial', () {
    test('commence à idle', () {
      final container = _makeContainer(_FakeRepo());
      addTearDown(container.dispose);
      final state = container.read(uploadDocumentsControllerProvider);
      expect(state, isA<UploadIdle>());
    });
  });

  group('UploadDocumentsController — validation locale', () {
    test('fichier > 10 Mo → FileError immédiat', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(uploadDocumentsControllerProvider.notifier)
          .uploadFiles(
            leaseId: 'lease-1',
            pickedFiles: [_file(size: 11 * 1024 * 1024)],
            defaultCategory: DocumentCategory.autre,
          );

      final state = container.read(uploadDocumentsControllerProvider);
      expect(state, isA<UploadCompleted>());
      final completed = state as UploadCompleted;
      expect(completed.successCount, 0);
      expect(completed.failureCount, 1);
      expect(completed.files.first, isA<FileError>());
      // Aucun appel réseau
      expect(repo.uploadCallCount, 0);
    });

    test('MIME hors whitelist → FileError immédiat', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(uploadDocumentsControllerProvider.notifier)
          .uploadFiles(
            leaseId: 'lease-1',
            pickedFiles: [_file(name: 'doc.docx', mime: 'application/msword')],
            defaultCategory: DocumentCategory.autre,
          );

      final state = container.read(uploadDocumentsControllerProvider);
      expect(state, isA<UploadCompleted>());
      final completed = state as UploadCompleted;
      expect(completed.failureCount, 1);
      expect(repo.uploadCallCount, 0);
    });
  });

  group('UploadDocumentsController — upload réussi', () {
    test('upload 1 fichier → completed(success=1, failure=0)', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(uploadDocumentsControllerProvider.notifier)
          .uploadFiles(
            leaseId: 'lease-1',
            pickedFiles: [_file()],
            defaultCategory: DocumentCategory.autre,
          );

      final state = container.read(uploadDocumentsControllerProvider);
      expect(state, isA<UploadCompleted>());
      final completed = state as UploadCompleted;
      expect(completed.successCount, 1);
      expect(completed.failureCount, 0);
      expect(completed.files.first, isA<FileSuccess>());
    });

    test('upload 3 fichiers réussis → successCount=3', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(uploadDocumentsControllerProvider.notifier)
          .uploadFiles(
            leaseId: 'lease-1',
            pickedFiles: [
              _file(),
              _file(name: 'img.jpg', mime: 'image/jpeg'),
              _file(name: 'p.png', mime: 'image/png'),
            ],
            defaultCategory: DocumentCategory.autre,
          );

      final completed =
          container.read(uploadDocumentsControllerProvider) as UploadCompleted;
      expect(completed.successCount, 3);
      expect(completed.failureCount, 0);
    });
  });

  group('UploadDocumentsController — upload échoué', () {
    test('1 fichier en erreur → completed(success=0, failure=1)', () async {
      final repo = _FakeRepo()..shouldFail = true;
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(uploadDocumentsControllerProvider.notifier)
          .uploadFiles(
            leaseId: 'lease-1',
            pickedFiles: [_file()],
            defaultCategory: DocumentCategory.autre,
          );

      final completed =
          container.read(uploadDocumentsControllerProvider) as UploadCompleted;
      expect(completed.successCount, 0);
      expect(completed.failureCount, 1);
      expect(completed.files.first, isA<FileError>());
    });
  });

  group('UploadDocumentsController.reset', () {
    test('reset → idle', () async {
      final repo = _FakeRepo();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(uploadDocumentsControllerProvider.notifier)
          .uploadFiles(
            leaseId: 'lease-1',
            pickedFiles: [_file()],
            defaultCategory: DocumentCategory.autre,
          );

      container.read(uploadDocumentsControllerProvider.notifier).reset();
      final state = container.read(uploadDocumentsControllerProvider);
      expect(state, isA<UploadIdle>());
    });
  });
}
