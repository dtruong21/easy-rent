import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeatingType.sqlValue', () {
    test('electric.sqlValue == "electric"', () {
      expect(HeatingType.electric.sqlValue, 'electric');
    });

    test('gas.sqlValue == "gas"', () {
      expect(HeatingType.gas.sqlValue, 'gas');
    });

    test('collective.sqlValue == "collective"', () {
      expect(HeatingType.collective.sqlValue, 'collective');
    });

    test('fuel.sqlValue == "fuel"', () {
      expect(HeatingType.fuel.sqlValue, 'fuel');
    });

    test('wood.sqlValue == "wood"', () {
      expect(HeatingType.wood.sqlValue, 'wood');
    });

    test('heatPump.sqlValue == "heat_pump"', () {
      expect(HeatingType.heatPump.sqlValue, 'heat_pump');
    });

    test('other.sqlValue == "other"', () {
      expect(HeatingType.other.sqlValue, 'other');
    });
  });

  group('HeatingType.labelFr', () {
    test('toutes les valeurs ont un label non vide', () {
      for (final h in HeatingType.values) {
        expect(h.labelFr, isNotEmpty);
      }
    });

    test('electric.labelFr == "Électrique"', () {
      expect(HeatingType.electric.labelFr, 'Électrique');
    });

    test('heatPump.labelFr == "Pompe à chaleur"', () {
      expect(HeatingType.heatPump.labelFr, 'Pompe à chaleur');
    });
  });

  group('HeatingType.fromSql', () {
    test('fromSql(null) → null', () {
      expect(HeatingType.fromSql(null), isNull);
    });

    test('fromSql("electric") → electric', () {
      expect(HeatingType.fromSql('electric'), HeatingType.electric);
    });

    test('fromSql("gas") → gas', () {
      expect(HeatingType.fromSql('gas'), HeatingType.gas);
    });

    test('fromSql("heat_pump") → heatPump', () {
      expect(HeatingType.fromSql('heat_pump'), HeatingType.heatPump);
    });

    test('fromSql("wood") → wood', () {
      expect(HeatingType.fromSql('wood'), HeatingType.wood);
    });

    test('fromSql valeur inconnue → fallback other', () {
      expect(HeatingType.fromSql('solar'), HeatingType.other);
    });

    test('fromSql chaîne vide → fallback other', () {
      expect(HeatingType.fromSql(''), HeatingType.other);
    });

    test(
      'round-trip fromSql(sqlValue) est idempotent pour toutes les valeurs',
      () {
        for (final h in HeatingType.values) {
          expect(HeatingType.fromSql(h.sqlValue), h);
        }
      },
    );
  });
}
