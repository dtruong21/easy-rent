import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PropertyType.fromSql', () {
    test('fromSql("appartement") → appartement', () {
      expect(PropertyType.fromSql('appartement'), PropertyType.appartement);
    });

    test('fromSql("maison") → maison', () {
      expect(PropertyType.fromSql('maison'), PropertyType.maison);
    });

    test('fromSql("studio") → studio', () {
      expect(PropertyType.fromSql('studio'), PropertyType.studio);
    });

    test('fromSql("autre") → autre', () {
      expect(PropertyType.fromSql('autre'), PropertyType.autre);
    });

    test('fromSql valeur inconnue → fallback autre', () {
      expect(PropertyType.fromSql('villa'), PropertyType.autre);
    });

    test('fromSql chaîne vide → fallback autre', () {
      expect(PropertyType.fromSql(''), PropertyType.autre);
    });

    test('fromSql casse différente → fallback autre (SQL est lowercase)', () {
      expect(PropertyType.fromSql('Appartement'), PropertyType.autre);
    });
  });

  group('PropertyType.sqlValue', () {
    test('appartement.sqlValue == "appartement"', () {
      expect(PropertyType.appartement.sqlValue, 'appartement');
    });

    test('maison.sqlValue == "maison"', () {
      expect(PropertyType.maison.sqlValue, 'maison');
    });

    test('studio.sqlValue == "studio"', () {
      expect(PropertyType.studio.sqlValue, 'studio');
    });

    test('autre.sqlValue == "autre"', () {
      expect(PropertyType.autre.sqlValue, 'autre');
    });

    test('round-trip fromSql(sqlValue) est idempotent', () {
      for (final t in PropertyType.values) {
        expect(PropertyType.fromSql(t.sqlValue), t);
      }
    });
  });

  group('PropertyType.labelFr', () {
    test('appartement.labelFr == "Appartement"', () {
      expect(PropertyType.appartement.labelFr, 'Appartement');
    });

    test('maison.labelFr == "Maison"', () {
      expect(PropertyType.maison.labelFr, 'Maison');
    });

    test('studio.labelFr == "Studio"', () {
      expect(PropertyType.studio.labelFr, 'Studio');
    });

    test('autre.labelFr == "Autre"', () {
      expect(PropertyType.autre.labelFr, 'Autre');
    });

    test('toutes les valeurs ont un label non vide', () {
      for (final t in PropertyType.values) {
        expect(t.labelFr, isNotEmpty);
      }
    });
  });
}
