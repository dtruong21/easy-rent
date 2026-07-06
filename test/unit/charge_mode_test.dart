/// Tests unitaires de [ChargeMode] (FEAT-042).
///
/// Couvre : sqlValue, labelFr, fromSqlOrNull (valide/null/inconnu).
library;

import 'package:easyrent/features/leases/domain/charge_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChargeMode.sqlValue', () {
    test('provisions → "provisions"', () {
      expect(ChargeMode.provisions.sqlValue, 'provisions');
    });

    test('forfait → "forfait"', () {
      expect(ChargeMode.forfait.sqlValue, 'forfait');
    });
  });

  group('ChargeMode.labelFr', () {
    test('provisions → "Provisions + régularisation"', () {
      expect(ChargeMode.provisions.labelFr, 'Provisions + régularisation');
    });

    test('forfait → "Forfait"', () {
      expect(ChargeMode.forfait.labelFr, 'Forfait');
    });
  });

  group('ChargeMode.fromSqlOrNull', () {
    test('null → null (le mode effectif est dérivé ailleurs)', () {
      expect(ChargeMode.fromSqlOrNull(null), isNull);
    });

    test('valeur inconnue → null (tolérance défensive)', () {
      expect(ChargeMode.fromSqlOrNull('some_future_mode'), isNull);
    });

    test('"provisions" → ChargeMode.provisions', () {
      expect(ChargeMode.fromSqlOrNull('provisions'), ChargeMode.provisions);
    });

    test('"forfait" → ChargeMode.forfait', () {
      expect(ChargeMode.fromSqlOrNull('forfait'), ChargeMode.forfait);
    });

    test('round-trip : sqlValue → fromSqlOrNull', () {
      for (final m in ChargeMode.values) {
        expect(ChargeMode.fromSqlOrNull(m.sqlValue), m);
      }
    });
  });
}
