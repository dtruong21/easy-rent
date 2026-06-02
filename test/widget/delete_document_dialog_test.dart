/// Tests widget de [DeleteDocumentDialog].
///
/// Couvre : variante normale vs variante legal_hold (textes différents).
library;

import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/presentation/widgets/delete_document_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Document _makeDoc({bool legalHold = false}) => Document(
  id: 'doc-1',
  landlordId: 'l1',
  leaseId: 'lease-1',
  category: legalHold ? DocumentCategory.bailSigne : DocumentCategory.autre,
  filename: 'test.pdf',
  storagePath: 'prod/l1/documents/doc-1.pdf',
  mimeType: 'application/pdf',
  sizeBytes: 1024,
  legalHold: legalHold,
  uploadedAt: DateTime(2026, 6, 1),
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

Widget _buildDialog({required Document document, VoidCallback? onConfirm}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => DeleteDocumentDialog(
              document: document,
              onConfirm: onConfirm ?? () {},
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DeleteDocumentDialog — variante normale (legalHold=false)', () {
    testWidgets('titre "Supprimer ce document ?"', (tester) async {
      await tester.pumpWidget(_buildDialog(document: _makeDoc()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Supprimer ce document ?'), findsOneWidget);
    });

    testWidgets('mention "irréversible" présente', (tester) async {
      await tester.pumpWidget(_buildDialog(document: _makeDoc()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('irréversible'), findsOneWidget);
    });

    testWidgets('bouton "Supprimer" visible', (tester) async {
      await tester.pumpWidget(_buildDialog(document: _makeDoc()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_confirm_delete')), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
    });

    testWidgets('bouton "Annuler" ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildDialog(document: _makeDoc()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_cancel_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_doc_dialog')), findsNothing);
    });

    testWidgets('bouton "Supprimer" appelle onConfirm', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _buildDialog(document: _makeDoc(), onConfirm: () => called = true),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      expect(called, true);
    });
  });

  group('DeleteDocumentDialog — variante legal_hold (legalHold=true)', () {
    testWidgets('titre "Document conservé (obligation légale)"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildDialog(document: _makeDoc(legalHold: true)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('obligation légale'), findsOneWidget);
    });

    testWidgets('mention loi 1989 présente', (tester) async {
      await tester.pumpWidget(
        _buildDialog(document: _makeDoc(legalHold: true)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1989'), findsOneWidget);
    });

    testWidgets('bouton "Masquer" visible (pas "Supprimer")', (tester) async {
      await tester.pumpWidget(
        _buildDialog(document: _makeDoc(legalHold: true)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Masquer'), findsOneWidget);
      expect(find.text('Supprimer'), findsNothing);
    });

    testWidgets('dialog legal_hold a la bonne clé', (tester) async {
      await tester.pumpWidget(
        _buildDialog(document: _makeDoc(legalHold: true)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('delete_doc_legal_hold_dialog')),
        findsOneWidget,
      );
    });
  });
}
