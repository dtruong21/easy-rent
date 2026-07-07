/// Tests widget de [ChargeRegularizationForm] (FEAT-029 V1.2 — correctif
/// review).
///
/// Couvre la garde "début <= fin" sur la période de référence :
/// - `isPeriodInvalid` reflète correctement l'inversion/l'égalité des bornes
/// - le message d'erreur explicite s'affiche sous le champ "Fin de période"
///   quand la période est invalide
/// - le message de validation dédié du champ "Dépenses réelles" (pas le
///   message générique "charges obligatoires")
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/charge_regularization/presentation/widgets/charge_regularization_form.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildForm({
  required DateTime periodStart,
  required DateTime periodEnd,
  int actualExpensesCents = 0,
}) {
  final controller = TextEditingController();
  return MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ChargeRegularizationForm(
          periodStart: periodStart,
          periodEnd: periodEnd,
          payments: const <Payment>[],
          actualExpensesController: controller,
          actualExpensesCents: actualExpensesCents,
          onPeriodStartChanged: (_) {},
          onPeriodEndChanged: (_) {},
          onActualExpensesChanged: (_) {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChargeRegularizationForm.isPeriodInvalid — correctif review', () {
    test('fin postérieure au début → valide (false)', () {
      final form = ChargeRegularizationForm(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        payments: const [],
        actualExpensesController: TextEditingController(),
        actualExpensesCents: 0,
        onPeriodStartChanged: (_) {},
        onPeriodEndChanged: (_) {},
        onActualExpensesChanged: (_) {},
      );
      expect(form.isPeriodInvalid, isFalse);
    });

    test('fin antérieure au début → invalide (true)', () {
      final form = ChargeRegularizationForm(
        periodStart: DateTime(2025, 12, 31),
        periodEnd: DateTime(2025, 1, 1),
        payments: const [],
        actualExpensesController: TextEditingController(),
        actualExpensesCents: 0,
        onPeriodStartChanged: (_) {},
        onPeriodEndChanged: (_) {},
        onActualExpensesChanged: (_) {},
      );
      expect(form.isPeriodInvalid, isTrue);
    });

    test('fin égale au début (période nulle) → invalide (true)', () {
      final sameDay = DateTime(2025, 6, 15);
      final form = ChargeRegularizationForm(
        periodStart: sameDay,
        periodEnd: sameDay,
        payments: const [],
        actualExpensesController: TextEditingController(),
        actualExpensesCents: 0,
        onPeriodStartChanged: (_) {},
        onPeriodEndChanged: (_) {},
        onActualExpensesChanged: (_) {},
      );
      expect(form.isPeriodInvalid, isTrue);
    });
  });

  group('ChargeRegularizationForm — période valide (fin > début)', () {
    testWidgets('aucun message d\'erreur affiché sous "Fin de période"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildForm(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('La date de fin doit être postérieure à la date de début'),
        findsNothing,
      );
    });
  });

  group('ChargeRegularizationForm — période invalide (fin <= début)', () {
    testWidgets(
      'fin AVANT début → message d\'erreur affiché sous "Fin de période"',
      (tester) async {
        await tester.pumpWidget(
          _buildForm(
            periodStart: DateTime(2025, 12, 31),
            periodEnd: DateTime(2025, 1, 1),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('La date de fin doit être postérieure à la date de début'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'fin ÉGALE au début (période nulle) → message d\'erreur affiché',
      (tester) async {
        final sameDay = DateTime(2025, 6, 15);
        await tester.pumpWidget(
          _buildForm(periodStart: sameDay, periodEnd: sameDay),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('La date de fin doit être postérieure à la date de début'),
          findsOneWidget,
        );
      },
    );
  });

  group('ChargeRegularizationForm — message de validation dédié (correctif '
      'review point 3)', () {
    testWidgets(
      'champ "Dépenses réelles" vide et soumis → message dédié, PAS le '
      'message générique "charges obligatoires"',
      (tester) async {
        await tester.pumpWidget(
          _buildForm(
            periodStart: DateTime(2025, 1, 1),
            periodEnd: DateTime(2025, 12, 31),
          ),
        );
        await tester.pumpAndSettle();

        final formField = tester.widget<TextFormField>(
          find.byKey(const Key('field_actual_expenses')),
        );
        final message = formField.validator?.call('');

        expect(
          message,
          'Le montant des dépenses réelles est obligatoire '
          '(saisir 0 si aucune)',
        );
        expect(
          message,
          isNot(contains('charges sont obligatoires')),
          reason:
              'Le message générique de MoneyValidators.validateChargesAmount '
              'ne doit pas fuiter tel quel sur un champ qui ne représente '
              'pas des "charges" au sens bail/paiement.',
        );
      },
    );
  });
}
