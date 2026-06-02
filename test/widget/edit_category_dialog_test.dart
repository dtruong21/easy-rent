/// Tests widget de [EditCategoryDialog].
///
/// Couvre : 5 options affichées, sélection retournée, annulation,
/// retour via showDialog typé.
library;

import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/presentation/widgets/edit_category_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Ouvre le dialog via showDialog avec callback [onSelect] optionnel.
Widget _buildDialog({
  DocumentCategory current = DocumentCategory.autre,
  void Function(DocumentCategory)? onSelect,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => EditCategoryDialog(
              currentCategory: current,
              onSelect: onSelect,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

/// Ouvre le dialog via showDialog typé et stocke le résultat dans
/// [onResult] pour les tests de valeur de retour.
Widget _buildDialogWithResult({
  required DocumentCategory current,
  required void Function(DocumentCategory?) onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final cat = await showDialog<DocumentCategory>(
              context: context,
              builder: (_) => EditCategoryDialog(currentCategory: current),
            );
            onResult(cat);
          },
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
  group('EditCategoryDialog', () {
    testWidgets('s\'ouvre avec la clé dialog', (tester) async {
      await tester.pumpWidget(_buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_category_dialog')), findsOneWidget);
    });

    testWidgets('titre "Modifier la catégorie" visible', (tester) async {
      await tester.pumpWidget(_buildDialog());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Modifier la catégorie'), findsOneWidget);
    });

    testWidgets('dropdown visible avec la valeur courante', (tester) async {
      await tester.pumpWidget(
        _buildDialog(current: DocumentCategory.bailSigne),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('category_dropdown')), findsOneWidget);
      // La catégorie courante est affichée dans le dropdown
      expect(find.text(DocumentCategory.bailSigne.label), findsOneWidget);
    });

    testWidgets('bouton "Annuler" ferme le dialog sans callback', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(_buildDialog(onSelect: (_) => called = true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_cancel_category')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_category_dialog')), findsNothing);
      expect(called, false);
    });

    testWidgets(
      'bouton "Valider" appelle onSelect avec la catégorie courante',
      (tester) async {
        DocumentCategory? selected;
        await tester.pumpWidget(
          _buildDialog(
            current: DocumentCategory.bailSigne,
            onSelect: (cat) => selected = cat,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Valider sans changer la sélection
        await tester.tap(find.byKey(const Key('btn_confirm_category')));
        await tester.pumpAndSettle();

        expect(selected, DocumentCategory.bailSigne);
      },
    );

    // BLOCKER-1 : showDialog typé doit résoudre à la catégorie sélectionnée
    // (pas null). Avant le fix, Navigator.pop() était appelé sans valeur →
    // showDialog retournait null → upload jamais lancé.
    testWidgets('showDialog résout à la catégorie sélectionnée (pas null)', (
      tester,
    ) async {
      DocumentCategory? result;
      await tester.pumpWidget(
        _buildDialogWithResult(
          current: DocumentCategory.quittanceScannee,
          onResult: (cat) => result = cat,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_confirm_category')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, DocumentCategory.quittanceScannee);
    });

    testWidgets('showDialog résout à null si annulé', (tester) async {
      DocumentCategory? result = DocumentCategory.autre; // valeur sentinelle
      await tester.pumpWidget(
        _buildDialogWithResult(
          current: DocumentCategory.quittanceScannee,
          onResult: (cat) => result = cat,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_cancel_category')));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
