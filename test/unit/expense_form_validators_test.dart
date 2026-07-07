/// Tests de [ExpenseFormValidators] — montant, date, période de rattachement
/// (obligatoire uniquement si récupérable — décret n°87-713).
library;

import 'package:easyrent/core/utils/expense_form_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseFormValidators.validateAmount', () {
    test('null → message obligatoire', () {
      expect(ExpenseFormValidators.validateAmount(null), isNotNull);
    });

    test('vide → message obligatoire', () {
      expect(ExpenseFormValidators.validateAmount(''), isNotNull);
    });

    test('0 → refusé (montant strictement positif)', () {
      expect(ExpenseFormValidators.validateAmount('0'), isNotNull);
    });

    test('montant positif valide → null', () {
      expect(ExpenseFormValidators.validateAmount('450,00'), isNull);
    });

    test('montant négatif → refusé', () {
      expect(ExpenseFormValidators.validateAmount('-10,00'), isNotNull);
    });
  });

  group('ExpenseFormValidators.validateExpenseDate', () {
    test('null → message obligatoire', () {
      expect(ExpenseFormValidators.validateExpenseDate(null), isNotNull);
    });

    test('date dans les bornes → null', () {
      expect(
        ExpenseFormValidators.validateExpenseDate(DateTime(2025, 3, 15)),
        isNull,
      );
    });

    test('date hors bornes (avant 1900) → refusée', () {
      expect(
        ExpenseFormValidators.validateExpenseDate(DateTime(1800, 1, 1)),
        isNotNull,
      );
    });
  });

  group('ExpenseFormValidators.validatePeriodStart — obligatoire seulement si '
      'récupérable', () {
    test('null + récupérable → message obligatoire', () {
      expect(
        ExpenseFormValidators.validatePeriodStart(null, isRecoverable: true),
        isNotNull,
      );
    });

    test('null + non-récupérable → null (optionnel)', () {
      expect(
        ExpenseFormValidators.validatePeriodStart(null, isRecoverable: false),
        isNull,
      );
    });

    test('date valide + récupérable → null', () {
      expect(
        ExpenseFormValidators.validatePeriodStart(
          DateTime(2025, 1, 1),
          isRecoverable: true,
        ),
        isNull,
      );
    });
  });

  group('ExpenseFormValidators.validatePeriodEnd', () {
    test('null + récupérable → message obligatoire', () {
      expect(
        ExpenseFormValidators.validatePeriodEnd(
          null,
          DateTime(2025, 1, 1),
          isRecoverable: true,
        ),
        isNotNull,
      );
    });

    test('null + non-récupérable → null (optionnel)', () {
      expect(
        ExpenseFormValidators.validatePeriodEnd(
          null,
          null,
          isRecoverable: false,
        ),
        isNull,
      );
    });

    test('fin antérieure ou égale au début → refusée', () {
      expect(
        ExpenseFormValidators.validatePeriodEnd(
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 1),
          isRecoverable: true,
        ),
        isNotNull,
      );
    });

    test('fin postérieure au début → null', () {
      expect(
        ExpenseFormValidators.validatePeriodEnd(
          DateTime(2025, 12, 31),
          DateTime(2025, 1, 1),
          isRecoverable: true,
        ),
        isNull,
      );
    });
  });

  group('ExpenseFormValidators.validateNotes', () {
    test('null → null (optionnel)', () {
      expect(ExpenseFormValidators.validateNotes(null), isNull);
    });

    test('texte court → null', () {
      expect(ExpenseFormValidators.validateNotes('décompte syndic'), isNull);
    });

    test('texte > 2000 caractères → refusé', () {
      final tooLong = 'a' * 2001;
      expect(ExpenseFormValidators.validateNotes(tooLong), isNotNull);
    });
  });
}
