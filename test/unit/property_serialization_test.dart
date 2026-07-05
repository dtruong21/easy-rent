import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _minimalProperty() => Property(
  id: 'p-1',
  landlordId: 'owner-1',
  name: 'Studio Lyon',
  address: '1 rue Molière, 69001 Lyon',
  type: PropertyType.studio,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: DateTime.utc(2024, 1, 2),
);

Property _fullProperty() => Property(
  id: 'p-2',
  landlordId: 'owner-2',
  name: 'Appartement Bordeaux',
  address: '5 cours de la Marne, 33000 Bordeaux',
  type: PropertyType.appartement,
  surfaceM2: 65.0,
  postalCode: '33000',
  city: 'Bordeaux',
  rooms: 4,
  bedrooms: 2,
  floor: 3,
  hasElevator: true,
  furnished: false,
  heatingType: HeatingType.gas,
  dpeLetter: 'C',
  dpeValueKwhM2Year: 180,
  gesLetter: 'B',
  constructionYear: 1985,
  createdAt: DateTime.utc(2024, 6, 1),
  updatedAt: DateTime.utc(2024, 6, 2),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property — backward compat (champs optionnels absents)', () {
    test(
      'désérialisation sans les nouveaux champs ne lève pas d\'exception',
      () {
        final json = <String, dynamic>{
          'id': 'p-legacy',
          'landlord_id': 'owner',
          'name': 'Vieille propriété',
          'address': '10 rue Vieille',
          'type': 'maison',
          'surface_m2': null,
          'created_at': '2023-01-01T00:00:00.000Z',
          'updated_at': '2023-01-01T00:00:00.000Z',
        };

        expect(() => Property.fromJson(json), returnsNormally);
      },
    );

    test('les champs optionnels sont null par défaut', () {
      final json = <String, dynamic>{
        'id': 'p-legacy',
        'landlord_id': 'owner',
        'name': 'Vieille propriété',
        'address': '10 rue Vieille',
        'type': 'maison',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      };

      final p = Property.fromJson(json);
      expect(p.postalCode, isNull);
      expect(p.city, isNull);
      expect(p.rooms, isNull);
      expect(p.bedrooms, isNull);
      expect(p.floor, isNull);
      expect(p.heatingType, isNull);
      expect(p.dpeLetter, isNull);
      expect(p.dpeValueKwhM2Year, isNull);
      expect(p.gesLetter, isNull);
      expect(p.constructionYear, isNull);
    });

    test('hasElevator et furnished sont false par défaut', () {
      final json = <String, dynamic>{
        'id': 'p-legacy',
        'landlord_id': 'owner',
        'name': 'Vieille propriété',
        'address': '10 rue Vieille',
        'type': 'maison',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      };

      final p = Property.fromJson(json);
      expect(p.hasElevator, isFalse);
      expect(p.furnished, isFalse);
    });
  });

  group('Property — round-trip JSON (minimal)', () {
    test('toJson puis fromJson restitue les champs obligatoires', () {
      final original = _minimalProperty();
      final restored = Property.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.hasElevator, isFalse);
      expect(restored.furnished, isFalse);
    });
  });

  group('Property — round-trip JSON (complet)', () {
    test('toJson puis fromJson restitue tous les nouveaux champs', () {
      final original = _fullProperty();
      final restored = Property.fromJson(original.toJson());

      expect(restored.postalCode, '33000');
      expect(restored.city, 'Bordeaux');
      expect(restored.rooms, 4);
      expect(restored.bedrooms, 2);
      expect(restored.floor, 3);
      expect(restored.hasElevator, isTrue);
      expect(restored.furnished, isFalse);
      expect(restored.heatingType, HeatingType.gas);
      expect(restored.dpeLetter, 'C');
      expect(restored.dpeValueKwhM2Year, 180);
      expect(restored.gesLetter, 'B');
      expect(restored.constructionYear, 1985);
    });

    test('heating_type est sérialisé en sqlValue', () {
      final json = _fullProperty().toJson();
      expect(json['heating_type'], 'gas');
    });

    test('heat_pump est sérialisé correctement', () {
      final p = _fullProperty().copyWith(heatingType: HeatingType.heatPump);
      expect(p.toJson()['heating_type'], 'heat_pump');
    });
  });

  group('Property — désérialisation heating_type depuis JSON', () {
    test('heating_type "heat_pump" → HeatingType.heatPump', () {
      final json = <String, dynamic>{
        'id': 'p-3',
        'landlord_id': 'owner',
        'name': 'Maison PAC',
        'address': '1 impasse',
        'type': 'maison',
        'heating_type': 'heat_pump',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };
      final p = Property.fromJson(json);
      expect(p.heatingType, HeatingType.heatPump);
    });

    test('heating_type null → heatingType null', () {
      final json = <String, dynamic>{
        'id': 'p-4',
        'landlord_id': 'owner',
        'name': 'Maison sans chauffage renseigné',
        'address': '1 impasse',
        'type': 'maison',
        'heating_type': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };
      final p = Property.fromJson(json);
      expect(p.heatingType, isNull);
    });
  });
}
