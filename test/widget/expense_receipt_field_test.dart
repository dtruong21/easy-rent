/// Tests widget de [ExpenseReceiptField] (FEAT-041b) — flux d'upload du
/// justificatif dans le formulaire dépense.
///
/// Couvre : bouton "Joindre" visible à l'état idle (recommandé, non
/// bloquant) ; affichage progression / succès / erreur selon l'état du
/// [ExpenseReceiptUploadController] ; bouton retirer disponible après succès.
library;

import 'dart:typed_data';

import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:easyrent/features/expenses/application/expense_receipt_upload_controller.dart';
import 'package:easyrent/features/expenses/domain/expense_receipt_upload_state.dart';
import 'package:easyrent/features/expenses/presentation/expense_receipt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository — jamais réellement appelé dans ces tests (on pilote
// l'état du contrôleur directement), mais requis pour le provider override.
// ---------------------------------------------------------------------------

class _FakeDocumentsRepository implements DocumentsRepository {
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

Widget _buildField({required ProviderContainer container}) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpenseReceiptField(propertyId: 'property-1'),
        ),
      ),
    ),
  );
}

void main() {
  group('ExpenseReceiptField — état idle (justificatif recommandé)', () {
    testWidgets('bouton "Joindre un justificatif" visible', (tester) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_pick_expense_receipt')), findsOneWidget);
      expect(find.textContaining('recommandé'), findsWidgets);
    });

    testWidgets(
      'mention "sans justificatif" affichée — non bloquant (décision #8)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            documentsRepositoryProvider.overrideWithValue(
              _FakeDocumentsRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildField(container: container));
        await tester.pumpAndSettle();

        expect(find.textContaining('sans justificatif'), findsOneWidget);
      },
    );
  });

  group('ExpenseReceiptField — upload en cours', () {
    testWidgets('affiche la progression et masque le bouton "Joindre"', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .state = const ExpenseReceiptUploadState.uploading(
        filename: 'facture.pdf',
        progress: 0.5,
      );

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Envoi de facture.pdf'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('btn_pick_expense_receipt')), findsNothing);
    });
  });

  group('ExpenseReceiptField — upload réussi', () {
    testWidgets(
      'affiche le nom de fichier + bouton retirer — pas de blocage sur '
      "l'absence de bail",
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            documentsRepositoryProvider.overrideWithValue(
              _FakeDocumentsRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(expenseReceiptUploadControllerProvider.notifier)
            .state = const ExpenseReceiptUploadState.success(
          filename: 'decompte-syndic.pdf',
          documentId: 'doc-receipt-1',
        );

        await tester.pumpWidget(_buildField(container: container));
        await tester.pumpAndSettle();

        expect(find.text('decompte-syndic.pdf'), findsOneWidget);
        expect(
          find.byKey(const Key('btn_remove_expense_receipt')),
          findsOneWidget,
        );
      },
    );

    testWidgets('bouton retirer remet le contrôleur à idle', (tester) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .state = const ExpenseReceiptUploadState.success(
        filename: 'decompte-syndic.pdf',
        documentId: 'doc-receipt-1',
      );

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_remove_expense_receipt')));
      await tester.pumpAndSettle();

      expect(
        container.read(expenseReceiptUploadControllerProvider),
        const ExpenseReceiptUploadState.idle(),
      );
      expect(find.byKey(const Key('btn_pick_expense_receipt')), findsOneWidget);
    });
  });

  group('ExpenseReceiptField — échec upload (non bloquant)', () {
    testWidgets('affiche le message d\'erreur + bouton réessayer', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(
            _FakeDocumentsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(expenseReceiptUploadControllerProvider.notifier)
          .state = const ExpenseReceiptUploadState.error(
        filename: 'facture.pdf',
        message: "Erreur lors de l'envoi. Réessayez.",
      );

      await tester.pumpWidget(_buildField(container: container));
      await tester.pumpAndSettle();

      expect(find.text("Erreur lors de l'envoi. Réessayez."), findsOneWidget);
      expect(
        find.byKey(const Key('btn_retry_expense_receipt')),
        findsOneWidget,
      );
    });
  });
}
