import 'package:easyrent/features/leases/presentation/widgets/close_lease_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildWithDialog({void Function(DateTime)? onClose}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => CloseLeaseDialog(onClose: onClose ?? (_) {}),
          ),
          child: const Text('Ouvrir dialog'),
        ),
      ),
    ),
  );
}

void main() {
  group('CloseLeaseDialog', () {
    testWidgets('affiche le titre "Clôturer ce bail"', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Clôturer ce bail'), findsOneWidget);
    });

    testWidgets('affiche la date de fin pré-remplie à aujourd\'hui', (
      tester,
    ) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final expectedDate =
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/'
          '${now.year}';

      expect(find.byKey(const Key('close_lease_date_display')), findsOneWidget);
      expect(find.text(expectedDate), findsOneWidget);
    });

    testWidgets('bouton "Annuler" présent', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_close_lease_cancel')), findsOneWidget);
    });

    testWidgets('bouton "Clôturer" présent', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_close_lease_confirm')), findsOneWidget);
    });

    testWidgets('tap "Annuler" ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_close_lease_cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Clôturer ce bail'), findsNothing);
    });

    testWidgets('tap "Clôturer" appelle onClose avec une date', (tester) async {
      DateTime? received;

      await tester.pumpWidget(_buildWithDialog(onClose: (d) => received = d));
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_close_lease_confirm')));
      await tester.pumpAndSettle();

      expect(received, isNotNull);
    });

    testWidgets(
      'tap "Clôturer" appelle onClose avec la date d\'aujourd\'hui par défaut',
      (tester) async {
        DateTime? received;
        final today = DateTime.now();

        await tester.pumpWidget(_buildWithDialog(onClose: (d) => received = d));
        await tester.tap(find.text('Ouvrir dialog'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_close_lease_confirm')));
        await tester.pumpAndSettle();

        expect(received!.year, today.year);
        expect(received!.month, today.month);
        expect(received!.day, today.day);
      },
    );

    testWidgets('tap "Clôturer" ferme le dialog', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_close_lease_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Clôturer ce bail'), findsNothing);
    });

    testWidgets('affiche le libellé "Date de fin effective"', (tester) async {
      await tester.pumpWidget(_buildWithDialog());
      await tester.tap(find.text('Ouvrir dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Date de fin effective'), findsOneWidget);
    });
  });
}
