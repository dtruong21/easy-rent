/// Tests widget de [DocumentListTile].
///
/// Couvre : affichage filename + chip catégorie + taille + date + menu actions.
library;

import 'dart:typed_data';

import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:easyrent/features/documents/presentation/widgets/document_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements DocumentsRepository {
  @override
  Future<String> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 300,
  }) async => 'https://example.com/signed';

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
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async => throw UnimplementedError();

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async =>
      const DocumentsQuota(totalBytes: 0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Document _makeDoc({
  String id = 'doc-1',
  DocumentCategory category = DocumentCategory.autre,
  String mimeType = 'application/pdf',
  bool legalHold = false,
  int sizeBytes = 2516582, // ~2.4 Mo
}) => Document(
  id: id,
  landlordId: 'l1',
  leaseId: 'lease-1',
  category: category,
  filename: 'document.pdf',
  storagePath: 'prod/l1/documents/$id.pdf',
  mimeType: mimeType,
  sizeBytes: sizeBytes,
  legalHold: legalHold,
  uploadedAt: DateTime(2026, 6, 1),
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

Widget _buildTile(Document document) {
  return ProviderScope(
    overrides: [documentsRepositoryProvider.overrideWithValue(_FakeRepo())],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DocumentListTile(document: document, leaseId: 'lease-1'),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DocumentListTile', () {
    testWidgets('affiche le nom du fichier', (tester) async {
      await tester.pumpWidget(_buildTile(_makeDoc()));
      await tester.pumpAndSettle();
      expect(find.text('document.pdf'), findsOneWidget);
    });

    testWidgets('clé de la tile correcte', (tester) async {
      await tester.pumpWidget(_buildTile(_makeDoc(id: 'doc-42')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc_tile_doc-42')), findsOneWidget);
    });

    testWidgets('affiche la catégorie dans le chip', (tester) async {
      await tester.pumpWidget(
        _buildTile(_makeDoc(category: DocumentCategory.bailSigne)),
      );
      await tester.pumpAndSettle();
      expect(find.text(DocumentCategory.bailSigne.label), findsOneWidget);
    });

    testWidgets('affiche la taille en Mo', (tester) async {
      await tester.pumpWidget(_buildTile(_makeDoc()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mo'), findsOneWidget);
    });

    testWidgets('affiche la date de l\'upload', (tester) async {
      await tester.pumpWidget(_buildTile(_makeDoc()));
      await tester.pumpAndSettle();
      expect(find.textContaining('01/06/2026'), findsOneWidget);
    });

    testWidgets('icône PDF rouge pour application/pdf', (tester) async {
      await tester.pumpWidget(
        _buildTile(_makeDoc(mimeType: 'application/pdf')),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    });

    testWidgets('icône image pour image/jpeg', (tester) async {
      await tester.pumpWidget(_buildTile(_makeDoc(mimeType: 'image/jpeg')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('menu actions visible', (tester) async {
      await tester.pumpWidget(_buildTile(_makeDoc()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc_menu_doc-1')), findsOneWidget);
    });

    testWidgets('badge "Obligation légale" visible si legalHold', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTile(_makeDoc(legalHold: true)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Obligation légale'), findsOneWidget);
    });

    testWidgets('badge "Obligation légale" absent si legalHold=false', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTile(_makeDoc(legalHold: false)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Obligation légale'), findsNothing);
    });

    testWidgets('tap sur menu → affiche les options', (tester) async {
      await tester.pumpWidget(_buildTile(_makeDoc()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('doc_menu_doc-1')));
      await tester.pumpAndSettle();

      expect(find.text('Télécharger'), findsOneWidget);
      expect(find.text('Modifier la catégorie'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
    });
  });
}
