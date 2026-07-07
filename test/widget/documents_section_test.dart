/// Tests widget de [DocumentsSection].
///
/// Couvre : empty state, liste avec docs, quota warning visible si applicable.
library;

import 'dart:typed_data';

import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:easyrent/features/documents/presentation/widgets/documents_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements DocumentsRepository {
  final List<Document> docs;
  final int quotaBytes;

  _FakeRepo({this.docs = const [], this.quotaBytes = 0});

  @override
  Future<List<Document>> listForLease(String leaseId) async =>
      docs.where((d) => d.leaseId == leaseId).toList();

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async =>
      DocumentsQuota(totalBytes: quotaBytes);

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
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async => throw UnimplementedError();

  @override
  Future<String> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 300,
  }) async => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Document _makeDoc(String id) => Document(
  id: id,
  landlordId: 'l1',
  leaseId: 'lease-1',
  category: DocumentCategory.autre,
  filename: '$id.pdf',
  storagePath: 'prod/l1/documents/$id.pdf',
  mimeType: 'application/pdf',
  sizeBytes: 1024,
  legalHold: false,
  uploadedAt: DateTime(2026, 6, 1),
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

Widget _buildSection({List<Document> docs = const [], int quotaBytes = 0}) {
  final repo = _FakeRepo(docs: docs, quotaBytes: quotaBytes);
  return ProviderScope(
    overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DocumentsSection(leaseId: 'lease-1'),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DocumentsSection', () {
    testWidgets('titre "Documents" visible', (tester) async {
      await tester.pumpWidget(_buildSection());
      await tester.pumpAndSettle();
      expect(find.text('Documents'), findsOneWidget);
    });

    testWidgets('drop zone toujours visible', (tester) async {
      await tester.pumpWidget(_buildSection());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_pick_files')), findsOneWidget);
    });

    testWidgets('empty state visible si aucun document', (tester) async {
      await tester.pumpWidget(_buildSection());
      await tester.pumpAndSettle();
      expect(find.text('Vos documents apparaîtront ici'), findsOneWidget);
    });

    testWidgets('liste des docs visible si non vide', (tester) async {
      final docs = [_makeDoc('doc-1'), _makeDoc('doc-2')];
      await tester.pumpWidget(_buildSection(docs: docs));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc_tile_doc-1')), findsOneWidget);
      expect(find.byKey(const Key('doc_tile_doc-2')), findsOneWidget);
    });

    testWidgets('empty state absent si des docs sont présents', (tester) async {
      await tester.pumpWidget(_buildSection(docs: [_makeDoc('doc-1')]));
      await tester.pumpAndSettle();
      expect(find.text('Vos documents apparaîtront ici'), findsNothing);
    });

    testWidgets('quota warning absent si quota < 100 Mo', (tester) async {
      await tester.pumpWidget(_buildSection(quotaBytes: 50 * 1024 * 1024));
      await tester.pumpAndSettle();
      expect(find.textContaining('dépassé 100 Mo'), findsNothing);
    });

    testWidgets('quota warning visible si quota >= 100 Mo', (tester) async {
      await tester.pumpWidget(_buildSection(quotaBytes: 110 * 1024 * 1024));
      await tester.pumpAndSettle();
      expect(find.textContaining('dépassé 100 Mo'), findsOneWidget);
    });

    testWidgets('quota indicator affiche la taille utilisée et la limite', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSection(quotaBytes: 5 * 1024 * 1024));
      await tester.pumpAndSettle();
      // ByteFormat.format(5*1024*1024) = "5 Mo", format(100*1024*1024) = "100 Mo"
      expect(find.textContaining('5 Mo'), findsOneWidget);
      expect(find.textContaining('100 Mo'), findsOneWidget);
    });
  });
}
