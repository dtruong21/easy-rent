/// Tests de [PaymentFormValidators] — chaque validator, cas nominal/limites/null.
library;

import 'package:easyrent/core/utils/payment_form_validators.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // validatePeriodStart
  // ---------------------------------------------------------------------------
  group('validatePeriodStart', () {
    test('null → erreur obligatoire', () {
      expect(PaymentFormValidators.validatePeriodStart(null), isNotNull);
    });

    test('date valide → null', () {
      expect(
        PaymentFormValidators.validatePeriodStart(DateTime(2024, 1, 1)),
        isNull,
      );
    });

    test('date min 1900-01-01 → null', () {
      expect(PaymentFormValidators.validatePeriodStart(DateTime(1900)), isNull);
    });

    test('date max 2100-12-31 → null', () {
      expect(
        PaymentFormValidators.validatePeriodStart(DateTime(2100, 12, 31)),
        isNull,
      );
    });

    test('avant 1900 → erreur bornes', () {
      expect(
        PaymentFormValidators.validatePeriodStart(DateTime(1850)),
        isNotNull,
      );
    });

    test('après 2100-12-31 → erreur bornes', () {
      expect(
        PaymentFormValidators.validatePeriodStart(DateTime(2101)),
        isNotNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // validatePeriodEnd
  // ---------------------------------------------------------------------------
  group('validatePeriodEnd', () {
    test('null → erreur obligatoire', () {
      expect(
        PaymentFormValidators.validatePeriodEnd(null, DateTime(2024, 1, 1)),
        isNotNull,
      );
    });

    test('end > start → null', () {
      expect(
        PaymentFormValidators.validatePeriodEnd(
          DateTime(2024, 1, 31),
          DateTime(2024, 1, 1),
        ),
        isNull,
      );
    });

    test('end == start → erreur postérieure', () {
      expect(
        PaymentFormValidators.validatePeriodEnd(
          DateTime(2024, 1, 1),
          DateTime(2024, 1, 1),
        ),
        isNotNull,
      );
    });

    test('end < start → erreur postérieure', () {
      expect(
        PaymentFormValidators.validatePeriodEnd(
          DateTime(2024, 1, 1),
          DateTime(2024, 2, 1),
        ),
        isNotNull,
      );
    });

    test('start null — pas de cross-check → null si end valide', () {
      expect(
        PaymentFormValidators.validatePeriodEnd(DateTime(2024, 1, 31), null),
        isNull,
      );
    });

    test('end avant 1900 → erreur bornes', () {
      expect(
        PaymentFormValidators.validatePeriodEnd(DateTime(1850), null),
        isNotNull,
      );
    });

    test('end après 2100-12-31 → erreur bornes', () {
      expect(
        PaymentFormValidators.validatePeriodEnd(DateTime(2200), null),
        isNotNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // validatePaidAt
  // ---------------------------------------------------------------------------
  group('validatePaidAt', () {
    test('null → erreur obligatoire', () {
      expect(PaymentFormValidators.validatePaidAt(null), isNotNull);
    });

    test('date passée → null (valide)', () {
      expect(
        PaymentFormValidators.validatePaidAt(DateTime(2024, 1, 1)),
        isNull,
      );
    });

    test('date future → null (prélèvement programmé autorisé)', () {
      expect(
        PaymentFormValidators.validatePaidAt(DateTime(2090, 1, 1)),
        isNull,
      );
    });

    test('avant 1900 → erreur bornes', () {
      expect(PaymentFormValidators.validatePaidAt(DateTime(1850)), isNotNull);
    });

    test('après 2100-12-31 → erreur bornes', () {
      expect(PaymentFormValidators.validatePaidAt(DateTime(2200)), isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // validateRentAmount
  // ---------------------------------------------------------------------------
  group('validateRentAmount', () {
    test('null → erreur obligatoire', () {
      expect(PaymentFormValidators.validateRentAmount(null), isNotNull);
    });

    test('chaîne vide → erreur obligatoire', () {
      expect(PaymentFormValidators.validateRentAmount(''), isNotNull);
    });

    test('espaces uniquement → erreur obligatoire', () {
      expect(PaymentFormValidators.validateRentAmount('   '), isNotNull);
    });

    test('"850" → null', () {
      expect(PaymentFormValidators.validateRentAmount('850'), isNull);
    });

    test('"850,00" (virgule FR) → null', () {
      expect(PaymentFormValidators.validateRentAmount('850,00'), isNull);
    });

    test('"0" → erreur positif (loyer doit être > 0)', () {
      expect(PaymentFormValidators.validateRentAmount('0'), isNotNull);
    });

    test('négatif "-10" → erreur positif', () {
      expect(PaymentFormValidators.validateRentAmount('-10'), isNotNull);
    });

    test('texte non numérique "abc" → erreur', () {
      expect(PaymentFormValidators.validateRentAmount('abc'), isNotNull);
    });

    test('montant > 1 000 000 € → erreur trop élevé', () {
      expect(PaymentFormValidators.validateRentAmount('1000001'), isNotNull);
    });

    test('montant exactement 1 000 000 € → null (limite acceptée)', () {
      expect(PaymentFormValidators.validateRentAmount('1000000'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // validateChargesAmount
  // ---------------------------------------------------------------------------
  group('validateChargesAmount', () {
    test('null → erreur obligatoire', () {
      expect(PaymentFormValidators.validateChargesAmount(null), isNotNull);
    });

    test('chaîne vide → erreur obligatoire', () {
      expect(PaymentFormValidators.validateChargesAmount(''), isNotNull);
    });

    test('"0" → null (0 accepté pour les charges)', () {
      expect(PaymentFormValidators.validateChargesAmount('0'), isNull);
    });

    test('"0,00" → null', () {
      expect(PaymentFormValidators.validateChargesAmount('0,00'), isNull);
    });

    test('"50" → null', () {
      expect(PaymentFormValidators.validateChargesAmount('50'), isNull);
    });

    test('négatif "-5" → erreur', () {
      expect(PaymentFormValidators.validateChargesAmount('-5'), isNotNull);
    });

    test('montant > 1 000 000 € → erreur trop élevé', () {
      expect(PaymentFormValidators.validateChargesAmount('1000001'), isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // validatePaymentMethod
  // ---------------------------------------------------------------------------
  group('validatePaymentMethod', () {
    test('null → erreur obligatoire', () {
      expect(PaymentFormValidators.validatePaymentMethod(null), isNotNull);
    });

    test('virement → null', () {
      expect(
        PaymentFormValidators.validatePaymentMethod(PaymentMethod.virement),
        isNull,
      );
    });

    test('cheque → null', () {
      expect(
        PaymentFormValidators.validatePaymentMethod(PaymentMethod.cheque),
        isNull,
      );
    });

    test('especes → null', () {
      expect(
        PaymentFormValidators.validatePaymentMethod(PaymentMethod.especes),
        isNull,
      );
    });

    test('prelevement → null', () {
      expect(
        PaymentFormValidators.validatePaymentMethod(PaymentMethod.prelevement),
        isNull,
      );
    });

    test('autre → null', () {
      expect(
        PaymentFormValidators.validatePaymentMethod(PaymentMethod.autre),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // validateNotes
  // ---------------------------------------------------------------------------
  group('validateNotes', () {
    test('null → null (optionnel)', () {
      expect(PaymentFormValidators.validateNotes(null), isNull);
    });

    test('chaîne vide → null', () {
      expect(PaymentFormValidators.validateNotes(''), isNull);
    });

    test('note courte → null', () {
      expect(PaymentFormValidators.validateNotes('Note courte'), isNull);
    });

    test('exactement 500 caractères → null', () {
      final note = 'a' * 500;
      expect(PaymentFormValidators.validateNotes(note), isNull);
    });

    test('501 caractères → erreur trop long', () {
      final note = 'a' * 501;
      expect(PaymentFormValidators.validateNotes(note), isNotNull);
    });
  });
}
