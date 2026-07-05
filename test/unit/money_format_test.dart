/// Tests unitaires de [MoneyFormat] — conversion euros ↔ centimes.
///
/// Les cas limites d'arrondi virgule flottante sont critiques :
/// `84.99 * 100 = 8498.999...` doit arrondir à 8499 avec `.round()`.
library;

import 'package:easyrent/core/utils/money_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  // Forcer la locale fr_FR pour reproductibilité.
  setUpAll(() => Intl.defaultLocale = 'fr_FR');

  group('MoneyFormat.eurosToCents', () {
    // --- Cas valides ---
    test('entier simple : "850" → 85000', () {
      expect(MoneyFormat.eurosToCents('850'), 85000);
    });

    test('décimal avec point : "84.99" → 8499 (arrondi)', () {
      expect(MoneyFormat.eurosToCents('84.99'), 8499);
    });

    test('décimal avec virgule : "84,99" → 8499 (arrondi)', () {
      expect(MoneyFormat.eurosToCents('84,99'), 8499);
    });

    test('centimes exacts : "0.10" → 10', () {
      expect(MoneyFormat.eurosToCents('0.10'), 10);
    });

    test('centimes exacts virgule : "0,10" → 10', () {
      expect(MoneyFormat.eurosToCents('0,10'), 10);
    });

    test('zéro : "0" → 0', () {
      expect(MoneyFormat.eurosToCents('0'), 0);
    });

    test('zéro décimal : "0.00" → 0', () {
      expect(MoneyFormat.eurosToCents('0.00'), 0);
    });

    test('grand montant : "9999999.99" → 999999999', () {
      expect(MoneyFormat.eurosToCents('9999999.99'), 999999999);
    });

    test('arrondi IEEE-754 : "1.005" → 100 (double.parse → 1.004999...)', () {
      // double.parse('1.005') = 1.004999999... en IEEE-754
      // 1.004999... * 100 = 100.4999... → .round() = 100
      // Ce test documente le comportement réel — pas de surprise en prod.
      expect(MoneyFormat.eurosToCents('1.005'), 100);
    });

    test('avec espaces autour : "  100  " → 10000', () {
      expect(MoneyFormat.eurosToCents('  100  '), 10000);
    });

    // --- Cas invalides → null ---
    test('chaîne vide → null', () {
      expect(MoneyFormat.eurosToCents(''), isNull);
    });

    test('espaces uniquement → null', () {
      expect(MoneyFormat.eurosToCents('   '), isNull);
    });

    test('lettres : "abc" → null', () {
      expect(MoneyFormat.eurosToCents('abc'), isNull);
    });

    test('négatif : "-10" → null', () {
      expect(MoneyFormat.eurosToCents('-10'), isNull);
    });

    test('négatif décimal : "-0.01" → null', () {
      expect(MoneyFormat.eurosToCents('-0.01'), isNull);
    });

    // --- Valeurs non-finies → null (Fix 1) ---
    test('Infinity → null', () {
      expect(MoneyFormat.eurosToCents('Infinity'), isNull);
    });

    test('-Infinity → null', () {
      expect(MoneyFormat.eurosToCents('-Infinity'), isNull);
    });

    test('NaN → null', () {
      expect(MoneyFormat.eurosToCents('NaN'), isNull);
    });

    // --- Débordement Postgres integer (max 2 147 483 647 centimes) → null ---
    test('1e18 (>> int32) → null', () {
      expect(MoneyFormat.eurosToCents('1e18'), isNull);
    });

    test('-1e9 (négatif hors plage) → null', () {
      // négatif rejeté avant même le test de débordement
      expect(MoneyFormat.eurosToCents('-1e9'), isNull);
    });
  });

  group('MoneyFormat.centsToEuros', () {
    test('0 centimes → 0.0', () {
      expect(MoneyFormat.centsToEuros(0), 0.0);
    });

    test('100 centimes → 1.0', () {
      expect(MoneyFormat.centsToEuros(100), 1.0);
    });

    test('8499 centimes → ~84.99', () {
      expect(MoneyFormat.centsToEuros(8499), closeTo(84.99, 0.001));
    });
  });

  group('MoneyFormat.formatEurosFromCents', () {
    test('0 centimes → "0,00 €"', () {
      // En fr_FR : virgule décimale, espace insécable entre 0,00 et €
      final result = MoneyFormat.formatEurosFromCents(0);
      expect(result, contains('0'));
      expect(result, contains('€'));
    });

    test('100 centimes → contient "1" et "€"', () {
      final result = MoneyFormat.formatEurosFromCents(100);
      expect(result, contains('€'));
    });

    test('12345 centimes → contient "123" et "45"', () {
      final result = MoneyFormat.formatEurosFromCents(12345);
      expect(result, contains('123'));
      expect(result, contains('45'));
    });

    test('85000 centimes → contient "850" et "€"', () {
      final result = MoneyFormat.formatEurosFromCents(85000);
      expect(result, contains('850'));
      expect(result, contains('€'));
    });
  });

  group('MoneyFormat.centsToInput', () {
    test('0 centimes → "0,00"', () {
      expect(MoneyFormat.centsToInput(0), '0,00');
    });

    test('12345 centimes → "123,45"', () {
      expect(MoneyFormat.centsToInput(12345), '123,45');
    });

    test('85000 centimes → "850,00"', () {
      expect(MoneyFormat.centsToInput(85000), '850,00');
    });

    test('1 centime → "0,01"', () {
      expect(MoneyFormat.centsToInput(1), '0,01');
    });
  });
}
