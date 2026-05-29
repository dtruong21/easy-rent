import 'package:easyrent/features/leases/presentation/widgets/active_lease_warning_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildWithDialog({VoidCallback? onConfirm}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ActiveLeaseWarningDialog(
              onConfirm: onConfirm ?? () {},
            ),
          ),
          child: const Text('Ouvrir dialog'),
        ),
      ),
    ),
  );
}

void main() {
  group('ActiveLeaseWarningDialog', () {
    testWidgets('affiche le titre "Bail actif existant"', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Bail actif existant'), findsOneWidget);
    });

    testWidgets('affiche le message d\'avertissement', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Ce bien a déjà un bail actif'),
        findsOneWidget,
      );
    });

    testWidgets('bouton "Annuler" présent', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_warning_cancel')), findsOneWidget);
    });

    testWidgets('bouton "Continuer" présent', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_warning_confirm')), findsOneWidget);
    });

    testWidgets('tap "Annuler" ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_warning_cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Bail actif existant'), findsNothing);
    });

    testWidgets('tap "Continuer" appelle le callback onConfirm', (
      tester,
    ) async {
      bool called = false;

      await tester.pumpWidget(_buildWithDialog(onConfirm: () => called = true));
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_warning_confirm')));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('tap "Continuer" ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_warning_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Bail actif existant'), findsNothing);
    });
  });
}
