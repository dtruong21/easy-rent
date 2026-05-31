/// Tests de [PaymentMethod] — round-trip fromSql/sqlValue/label.
library;

import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentMethod.fromSql', () {
    test('"virement" → PaymentMethod.virement', () {
      expect(PaymentMethod.fromSql('virement'), PaymentMethod.virement);
    });

    test('"cheque" → PaymentMethod.cheque', () {
      expect(PaymentMethod.fromSql('cheque'), PaymentMethod.cheque);
    });

    test('"especes" → PaymentMethod.especes', () {
      expect(PaymentMethod.fromSql('especes'), PaymentMethod.especes);
    });

    test('"prelevement" → PaymentMethod.prelevement', () {
      expect(PaymentMethod.fromSql('prelevement'), PaymentMethod.prelevement);
    });

    test('"autre" → PaymentMethod.autre', () {
      expect(PaymentMethod.fromSql('autre'), PaymentMethod.autre);
    });

    test('valeur inconnue → PaymentMethod.autre (tolérance défensive)', () {
      expect(PaymentMethod.fromSql('inconnu'), PaymentMethod.autre);
    });

    test('chaîne vide → PaymentMethod.autre (tolérance défensive)', () {
      expect(PaymentMethod.fromSql(''), PaymentMethod.autre);
    });
  });

  group('PaymentMethod.sqlValue', () {
    test('virement.sqlValue == "virement"', () {
      expect(PaymentMethod.virement.sqlValue, 'virement');
    });

    test('cheque.sqlValue == "cheque"', () {
      expect(PaymentMethod.cheque.sqlValue, 'cheque');
    });

    test('especes.sqlValue == "especes"', () {
      expect(PaymentMethod.especes.sqlValue, 'especes');
    });

    test('prelevement.sqlValue == "prelevement"', () {
      expect(PaymentMethod.prelevement.sqlValue, 'prelevement');
    });

    test('autre.sqlValue == "autre"', () {
      expect(PaymentMethod.autre.sqlValue, 'autre');
    });
  });

  group('PaymentMethod.label', () {
    test('virement.label == "Virement"', () {
      expect(PaymentMethod.virement.label, 'Virement');
    });

    test('cheque.label == "Chèque"', () {
      expect(PaymentMethod.cheque.label, 'Chèque');
    });

    test('especes.label == "Espèces"', () {
      expect(PaymentMethod.especes.label, 'Espèces');
    });

    test('prelevement.label == "Prélèvement automatique"', () {
      expect(PaymentMethod.prelevement.label, 'Prélèvement automatique');
    });

    test('autre.label == "Autre"', () {
      expect(PaymentMethod.autre.label, 'Autre');
    });
  });

  group('Round-trip fromSql → sqlValue', () {
    for (final method in PaymentMethod.values) {
      test('${method.name} : round-trip cohérent', () {
        final roundTripped = PaymentMethod.fromSql(method.sqlValue);
        expect(roundTripped, method);
      });
    }
  });
}
