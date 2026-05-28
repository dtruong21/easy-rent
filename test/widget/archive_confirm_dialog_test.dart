import 'package:easyrent/features/properties/presentation/widgets/archive_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper : montre le dialog directement dans un Scaffold minimal.
// ---------------------------------------------------------------------------

Widget _buildDialog({required bool hasActiveLease, VoidCallback? onConfirm}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ArchiveConfirmDialog(
          propertyName: 'Appart Test',
          hasActiveLease: hasActiveLease,
          onConfirm: onConfirm ?? () {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ArchiveConfirmDialog', () {
    // -----------------------------------------------------------------------
    // Titre commun aux deux variantes
    // -----------------------------------------------------------------------
    testWidgets('titre "Archiver ce bien ?" présent (sans bail)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: false));
      expect(find.text('Archiver ce bien ?'), findsOneWidget);
    });

    testWidgets('titre "Archiver ce bien ?" présent (avec bail actif)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: true));
      expect(find.text('Archiver ce bien ?'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Variante standard (sans bail actif)
    // -----------------------------------------------------------------------
    testWidgets('sans bail actif — message standard affiché', (tester) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: false));

      // Vérifier que le message standard (sans mention "bail actif") est présent.
      expect(find.textContaining('Appart Test'), findsOneWidget);
      expect(find.textContaining('n\'apparaîtra plus'), findsOneWidget);
    });

    testWidgets('sans bail actif — pas de mention "bail actif"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: false));
      expect(find.textContaining('bail actif'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // Variante renforcée (avec bail actif)
    // -----------------------------------------------------------------------
    testWidgets('avec bail actif — message renforcé affiché', (tester) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: true));
      expect(find.textContaining('bail actif'), findsOneWidget);
    });

    testWidgets('avec bail actif — avertissement "Êtes-vous sûr" visible', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: true));
      expect(find.textContaining('sûr'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Actions
    // -----------------------------------------------------------------------
    testWidgets('bouton "Annuler" présent dans les deux variantes', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: false));
      expect(find.text('Annuler'), findsOneWidget);

      await tester.pumpWidget(_buildDialog(hasActiveLease: true));
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('bouton "Archiver" présent dans les deux variantes', (
      tester,
    ) async {
      await tester.pumpWidget(_buildDialog(hasActiveLease: false));
      expect(find.text('Archiver'), findsOneWidget);

      await tester.pumpWidget(_buildDialog(hasActiveLease: true));
      expect(find.text('Archiver'), findsOneWidget);
    });

    testWidgets('tap "Archiver" appelle onConfirm', (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        _buildDialog(hasActiveLease: false, onConfirm: () => confirmed = true),
      );

      await tester.tap(find.text('Archiver'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });

    testWidgets('tap "Archiver" (bail actif) appelle onConfirm', (
      tester,
    ) async {
      bool confirmed = false;

      await tester.pumpWidget(
        _buildDialog(hasActiveLease: true, onConfirm: () => confirmed = true),
      );

      await tester.tap(find.text('Archiver'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });
  });
}
