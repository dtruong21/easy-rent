/// Tests widget de [ExpenseListTile] — visibilité de la récurrence
/// (FEAT-041d).
///
/// Une échéance virtuelle n'existe nulle part en base : si la ligne ne
/// disait pas que la dépense revient, les totaux et le graphique
/// afficheraient des montants qu'aucune ligne visible ne justifie —
/// indiscernable d'un bug.
library;

import 'package:easyrent/core/finance/expense_recurrence.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:easyrent/features/expenses/presentation/expense_list_tile.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _expense({
  ExpenseRecurrence recurrence = ExpenseRecurrence.none,
  DateTime? recurrenceEndDate,
}) => Expense(
  id: 'exp-1',
  landlordId: 'landlord-1',
  propertyId: 'property-1',
  amountCents: 15000,
  expenseDate: DateTime(2026, 1, 15),
  nature: ExpenseNature.condoCharges,
  category: ExpenseCategory.nonRecoverable,
  categoryOverridden: true,
  periodYear: 2026,
  recurrence: recurrence,
  recurrenceEndDate: recurrenceEndDate,
  createdAt: DateTime(2026, 1, 15),
  updatedAt: DateTime(2026, 1, 15),
);

Widget _wrap(Expense expense) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  locale: const Locale('fr'),
  supportedLocales: supportedLocales,
  home: Scaffold(body: ExpenseListTile(expense: expense)),
);

void main() {
  testWidgets('dépense ponctuelle → aucun badge de récurrence', (tester) async {
    await tester.pumpWidget(_wrap(_expense()));

    expect(
      find.byKey(const Key('expense_recurrence_chip_exp-1')),
      findsNothing,
    );
  });

  testWidgets('dépense trimestrielle sans fin → badge « Tous les '
      'trimestres »', (tester) async {
    await tester.pumpWidget(
      _wrap(_expense(recurrence: ExpenseRecurrence.quarterly)),
    );

    expect(
      find.byKey(const Key('expense_recurrence_chip_exp-1')),
      findsOneWidget,
    );
    expect(find.text('Tous les trimestres'), findsOneWidget);
  });

  testWidgets('dépense mensuelle bornée → le badge annonce la date de fin', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _expense(
          recurrence: ExpenseRecurrence.monthly,
          recurrenceEndDate: DateTime(2027, 12, 31),
        ),
      ),
    );

    expect(find.text('Tous les mois jusqu\'au 31/12/2027'), findsOneWidget);
  });
}
