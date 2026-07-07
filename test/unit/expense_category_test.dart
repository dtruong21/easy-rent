/// Tests de [ExpenseCategory] — round-trip fromSql/sqlValue/label.
library;

import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseCategory.fromSql', () {
    test('"recoverable" → ExpenseCategory.recoverable', () {
      expect(
        ExpenseCategory.fromSql('recoverable'),
        ExpenseCategory.recoverable,
      );
    });

    test('"non_recoverable" → ExpenseCategory.nonRecoverable', () {
      expect(
        ExpenseCategory.fromSql('non_recoverable'),
        ExpenseCategory.nonRecoverable,
      );
    });

    test('valeur inconnue → ExpenseCategory.nonRecoverable (tolérance '
        'conservative — décret 87-713)', () {
      expect(
        ExpenseCategory.fromSql('inconnu'),
        ExpenseCategory.nonRecoverable,
      );
    });
  });

  group('ExpenseCategory.sqlValue', () {
    test('recoverable.sqlValue == "recoverable"', () {
      expect(ExpenseCategory.recoverable.sqlValue, 'recoverable');
    });

    test('nonRecoverable.sqlValue == "non_recoverable"', () {
      expect(ExpenseCategory.nonRecoverable.sqlValue, 'non_recoverable');
    });
  });

  group('Round-trip fromSql → sqlValue', () {
    for (final category in ExpenseCategory.values) {
      test('${category.name} : round-trip cohérent', () {
        final roundTripped = ExpenseCategory.fromSql(category.sqlValue);
        expect(roundTripped, category);
      });
    }
  });
}
