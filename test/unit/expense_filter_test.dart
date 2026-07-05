/// Tests de [ExpenseFilter.apply] — filtre exercice/catégorie/nature.
library;

import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_filter.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _makeExpense({
  String id = 'exp-1',
  ExpenseCategory category = ExpenseCategory.recoverable,
  ExpenseNature nature = ExpenseNature.condoCharges,
  int periodYear = 2025,
  int amountCents = 10000,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: 'prop-1',
  amountCents: amountCents,
  expenseDate: DateTime(periodYear, 3, 15),
  nature: nature,
  category: category,
  periodYear: periodYear,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  group('ExpenseFilter.empty', () {
    test('isActive == false', () {
      expect(ExpenseFilter.empty.isActive, isFalse);
    });

    test('apply ne filtre rien', () {
      final expenses = [
        _makeExpense(id: 'a', periodYear: 2024),
        _makeExpense(id: 'b', periodYear: 2025),
      ];
      expect(ExpenseFilter.empty.apply(expenses), hasLength(2));
    });
  });

  group('ExpenseFilter — filtre periodYear', () {
    test('ne garde que l\'exercice sélectionné', () {
      final expenses = [
        _makeExpense(id: 'a', periodYear: 2024),
        _makeExpense(id: 'b', periodYear: 2025),
        _makeExpense(id: 'c', periodYear: 2025),
      ];
      const filter = ExpenseFilter(periodYear: 2025);
      final result = filter.apply(expenses);
      expect(result, hasLength(2));
      expect(result.map((e) => e.id), containsAll(['b', 'c']));
    });
  });

  group('ExpenseFilter — filtre category', () {
    test('ne garde que la catégorie sélectionnée', () {
      final expenses = [
        _makeExpense(id: 'a', category: ExpenseCategory.recoverable),
        _makeExpense(id: 'b', category: ExpenseCategory.nonRecoverable),
      ];
      const filter = ExpenseFilter(category: ExpenseCategory.nonRecoverable);
      final result = filter.apply(expenses);
      expect(result, hasLength(1));
      expect(result.single.id, 'b');
    });
  });

  group('ExpenseFilter — filtre nature', () {
    test('ne garde que la nature sélectionnée', () {
      final expenses = [
        _makeExpense(id: 'a', nature: ExpenseNature.condoCharges),
        _makeExpense(id: 'b', nature: ExpenseNature.propertyTax),
      ];
      const filter = ExpenseFilter(nature: ExpenseNature.propertyTax);
      final result = filter.apply(expenses);
      expect(result, hasLength(1));
      expect(result.single.id, 'b');
    });
  });

  group('ExpenseFilter — combinaison de critères', () {
    test('applique tous les critères en ET logique', () {
      final expenses = [
        _makeExpense(
          id: 'match',
          periodYear: 2025,
          category: ExpenseCategory.recoverable,
          nature: ExpenseNature.condoCharges,
        ),
        _makeExpense(
          id: 'wrong-year',
          periodYear: 2024,
          category: ExpenseCategory.recoverable,
          nature: ExpenseNature.condoCharges,
        ),
        _makeExpense(
          id: 'wrong-category',
          periodYear: 2025,
          category: ExpenseCategory.nonRecoverable,
          nature: ExpenseNature.condoCharges,
        ),
      ];
      const filter = ExpenseFilter(
        periodYear: 2025,
        category: ExpenseCategory.recoverable,
        nature: ExpenseNature.condoCharges,
      );
      final result = filter.apply(expenses);
      expect(result, hasLength(1));
      expect(result.single.id, 'match');
    });
  });
}
