/// Tests de [ExpenseTotals] — somme de LIGNES vs somme sur une FENÊTRE de
/// temps (FEAT-041d).
///
/// La distinction est le cœur de la lisibilité : le total d'une liste
/// filtrée doit rester la somme exacte des lignes affichées, tandis qu'un
/// total qui annonce « les 12 derniers mois » doit compter chaque échéance
/// d'une dépense récurrente.
library;

import 'package:easyrent/core/finance/expense_recurrence.dart';
import 'package:easyrent/features/expenses/application/expenses_provider.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _expense({
  String id = 'exp-1',
  required int amountCents,
  required DateTime expenseDate,
  ExpenseCategory category = ExpenseCategory.nonRecoverable,
  ExpenseNature nature = ExpenseNature.condoCharges,
  ExpenseRecurrence recurrence = ExpenseRecurrence.none,
  DateTime? recurrenceEndDate,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: 'property-1',
  amountCents: amountCents,
  expenseDate: expenseDate,
  nature: nature,
  category: category,
  periodYear: expenseDate.year,
  recurrence: recurrence,
  recurrenceEndDate: recurrenceEndDate,
  createdAt: expenseDate,
  updatedAt: expenseDate,
);

void main() {
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);

  group('ExpenseTotals.fromExpenses — somme des lignes', () {
    test('une dépense récurrente compte pour UNE ligne, quel que soit son '
        'rythme (le total d\'une liste = ce qui est affiché)', () {
      final totals = ExpenseTotals.fromExpenses([
        _expense(
          amountCents: 15000,
          expenseDate: DateTime(2026, 1, 15),
          recurrence: ExpenseRecurrence.quarterly,
        ),
      ]);

      expect(totals.nonRecoverableCents, 15000);
    });
  });

  group('ExpenseTotals.overWindow — somme sur une fenêtre', () {
    test('dépense ponctuelle dans la fenêtre → comptée une fois', () {
      final totals = ExpenseTotals.overWindow(
        expenses: [
          _expense(amountCents: 15000, expenseDate: DateTime(2026, 3, 1)),
        ],
        from: from,
        to: to,
      );

      expect(totals.nonRecoverableCents, 15000);
    });

    test('dépense ponctuelle hors fenêtre → ignorée', () {
      final totals = ExpenseTotals.overWindow(
        expenses: [
          _expense(amountCents: 15000, expenseDate: DateTime(2025, 3, 1)),
        ],
        from: from,
        to: to,
      );

      expect(totals.totalCents, 0);
    });

    test('dépense trimestrielle → ses 4 échéances de l\'année', () {
      final totals = ExpenseTotals.overWindow(
        expenses: [
          _expense(
            amountCents: 15000,
            expenseDate: DateTime(2026, 1, 15),
            recurrence: ExpenseRecurrence.quarterly,
          ),
        ],
        from: from,
        to: to,
      );

      expect(totals.nonRecoverableCents, 60000);
    });

    test('la date de fin borne le total', () {
      final totals = ExpenseTotals.overWindow(
        expenses: [
          _expense(
            amountCents: 15000,
            expenseDate: DateTime(2026, 1, 15),
            recurrence: ExpenseRecurrence.quarterly,
            recurrenceEndDate: DateTime(2026, 5, 1),
          ),
        ],
        from: from,
        to: to,
      );

      // Janvier et avril seulement.
      expect(totals.nonRecoverableCents, 30000);
    });

    test('récupérable et non récupérable restent séparés, échéances '
        'comprises', () {
      final totals = ExpenseTotals.overWindow(
        expenses: [
          _expense(
            id: 'e1',
            amountCents: 10000,
            expenseDate: DateTime(2026, 1, 1),
            category: ExpenseCategory.recoverable,
            recurrence: ExpenseRecurrence.monthly,
          ),
          _expense(
            id: 'e2',
            amountCents: 120000,
            expenseDate: DateTime(2026, 9, 1),
            nature: ExpenseNature.propertyTax,
          ),
        ],
        from: from,
        to: to,
      );

      expect(totals.recoverableCents, 120000); // 12 × 10000
      expect(totals.nonRecoverableCents, 120000);
      expect(totals.totalCents, 240000);
    });
  });
}
