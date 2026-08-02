/// Tests unitaires du [ExpenseReceiptUploadController] (FEAT-041b).
library;

import 'dart:typed_data';

import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:easyrent/features/expenses/application/expense_receipt_upload_controller.dart';
import 'package:easyrent/features/expenses/domain/expense_receipt_upload_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeDocumentsRepository implements DocumentsRepository {
  bool uploadShouldFail = false;
  String? lastLeaseId;
  String? lastPropertyId;
  DocumentCategory? lastCategory;
  int uploadCallCount = 0;

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
    uploadCallCount++;
    lastLeaseId = leaseId;
    lastPropertyId = propertyId;
    lastCategory = category;
    if (uploadShouldFail) throw Exception('upload failed');
    onProgress?.call(0.0);
    onProgress?.call(1.0);
    return Document(
      id: 'receipt-doc-$uploadCallCount',
      landlordId: 'landlord-1',
      leaseId: leaseId,
      propertyId: propertyId,
      category: category,
      filename: filename,
      storagePath: 'documents/landlord-1/receipt-doc-$uploadCallCount.pdf',
      mimeType: mimeType,
      sizeBytes: bytes.length,
      legalHold: category.requiresLegalHold,
      uploadedAt: DateTime(2026, 7, 1),
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
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
    String documentId, {
    int expiresInSeconds = 300,
  }) async => throw UnimplementedError();

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async =>
      const DocumentsQuota(totalBytes: 0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(_FakeDocumentsRepository repo) {
  return ProviderContainer(
    overrides: [
      documentsRepositoryProvider.overrideWithValue(repo),
      // FEAT-056 : le plafond de taille (10 Mo, palier free — inchangé pour
      // ces tests) est désormais lu via `quotaLimitProvider`, qui dérive de
      // `landlordTierProvider`.
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(
          const LandlordTierSnapshot(tier: SubscriptionTier.free),
        ),
      ),
    ],
  );
}

Uint8List _bytes(int size) => Uint8List(size);

void main() {
  group('ExpenseReceiptUploadController — état initial', () {
    test('commence à idle', () {
      final container = _makeContainer(_FakeDocumentsRepository());
      addTearDown(container.dispose);
      expect(
        container.read(expenseReceiptUploadControllerProvider),
        const ExpenseReceiptUploadState.idle(),
      );
    });
  });

  group('ExpenseReceiptUploadController — upload réussi', () {
    test(
      'upload avec propertyId seul (aucun bail) → success + documentId',
      () async {
        final repo = _FakeDocumentsRepository();
        final container = _makeContainer(repo);
        addTearDown(container.dispose);

        // Résout landlordTierProvider avant l'action (le read() synchrone dans

        // upload() tomberait sinon sur le fallback anonyme -> quota 0, cf.

        // scenario_limit_controller_test.dart, même piège).

        await container.read(landlordTierProvider.future);

        await container
            .read(expenseReceiptUploadControllerProvider.notifier)
            .upload(
              propertyId: 'property-1',
              filename: 'decompte-syndic.pdf',
              bytes: _bytes(1024),
              mimeType: 'application/pdf',
            );

        final state = container.read(expenseReceiptUploadControllerProvider);
        expect(state, isA<ReceiptSuccess>());
        expect((state as ReceiptSuccess).documentId, 'receipt-doc-1');
        expect(repo.lastPropertyId, 'property-1');
        expect(repo.lastLeaseId, isNull);
        expect(repo.lastCategory, DocumentCategory.expenseReceipt);
      },
    );

    test('upload avec propertyId + leaseId transmet les deux', () async {
      final repo = _FakeDocumentsRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Résout landlordTierProvider avant l'action (le read() synchrone dans

      // upload() tomberait sinon sur le fallback anonyme -> quota 0, cf.

      // scenario_limit_controller_test.dart, même piège).

      await container.read(landlordTierProvider.future);

      await container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .upload(
            propertyId: 'property-1',
            leaseId: 'lease-1',
            filename: 'facture.pdf',
            bytes: _bytes(1024),
            mimeType: 'application/pdf',
          );

      expect(repo.lastPropertyId, 'property-1');
      expect(repo.lastLeaseId, 'lease-1');
    });

    test('catégorie transmise est toujours expenseReceipt', () async {
      final repo = _FakeDocumentsRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Résout landlordTierProvider avant l'action (le read() synchrone dans

      // upload() tomberait sinon sur le fallback anonyme -> quota 0, cf.

      // scenario_limit_controller_test.dart, même piège).

      await container.read(landlordTierProvider.future);

      await container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .upload(
            propertyId: 'property-1',
            filename: 'facture.pdf',
            bytes: _bytes(1024),
            mimeType: 'application/pdf',
          );

      expect(repo.lastCategory, DocumentCategory.expenseReceipt);
    });
  });

  group('ExpenseReceiptUploadController — validation locale', () {
    test('fichier > 10 Mo → error immédiat, pas d\'appel réseau', () async {
      final repo = _FakeDocumentsRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Résout landlordTierProvider avant l'action (le read() synchrone dans

      // upload() tomberait sinon sur le fallback anonyme -> quota 0, cf.

      // scenario_limit_controller_test.dart, même piège).

      await container.read(landlordTierProvider.future);

      await container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .upload(
            propertyId: 'property-1',
            filename: 'gros-fichier.pdf',
            bytes: _bytes(11 * 1024 * 1024),
            mimeType: 'application/pdf',
          );

      final state = container.read(expenseReceiptUploadControllerProvider);
      expect(state, isA<ReceiptError>());
      expect(repo.uploadCallCount, 0);
    });

    test('MIME hors whitelist → error immédiat, pas d\'appel réseau', () async {
      final repo = _FakeDocumentsRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Résout landlordTierProvider avant l'action (le read() synchrone dans

      // upload() tomberait sinon sur le fallback anonyme -> quota 0, cf.

      // scenario_limit_controller_test.dart, même piège).

      await container.read(landlordTierProvider.future);

      await container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .upload(
            propertyId: 'property-1',
            filename: 'doc.docx',
            bytes: _bytes(1024),
            mimeType: 'application/msword',
          );

      final state = container.read(expenseReceiptUploadControllerProvider);
      expect(state, isA<ReceiptError>());
      expect(repo.uploadCallCount, 0);
    });
  });

  group('ExpenseReceiptUploadController — échec upload distant', () {
    test('exception du repo → état error, formulaire reste soumettable '
        '(non bloquant)', () async {
      final repo = _FakeDocumentsRepository()..uploadShouldFail = true;
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Résout landlordTierProvider avant l'action (le read() synchrone dans

      // upload() tomberait sinon sur le fallback anonyme -> quota 0, cf.

      // scenario_limit_controller_test.dart, même piège).

      await container.read(landlordTierProvider.future);

      await container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .upload(
            propertyId: 'property-1',
            filename: 'facture.pdf',
            bytes: _bytes(1024),
            mimeType: 'application/pdf',
          );

      final state = container.read(expenseReceiptUploadControllerProvider);
      expect(state, isA<ReceiptError>());
    });
  });

  group('ExpenseReceiptUploadController — reset', () {
    test('reset() remet l\'état à idle après un succès', () async {
      final repo = _FakeDocumentsRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Résout landlordTierProvider avant l'action (le read() synchrone dans

      // upload() tomberait sinon sur le fallback anonyme -> quota 0, cf.

      // scenario_limit_controller_test.dart, même piège).

      await container.read(landlordTierProvider.future);

      await container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .upload(
            propertyId: 'property-1',
            filename: 'facture.pdf',
            bytes: _bytes(1024),
            mimeType: 'application/pdf',
          );
      expect(
        container.read(expenseReceiptUploadControllerProvider),
        isA<ReceiptSuccess>(),
      );

      container.read(expenseReceiptUploadControllerProvider.notifier).reset();
      expect(
        container.read(expenseReceiptUploadControllerProvider),
        const ExpenseReceiptUploadState.idle(),
      );
    });
  });
}
