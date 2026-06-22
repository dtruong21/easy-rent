import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Tenant _minimalTenant() => Tenant(
  id: 't-1',
  landlordId: 'owner-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean.dupont@test.com',
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: DateTime.utc(2024, 1, 2),
);

Tenant _fullTenant() => Tenant(
  id: 't-2',
  landlordId: 'owner-2',
  firstName: 'Marie',
  lastName: 'Martin',
  email: 'marie.martin@test.com',
  phone: '06 12 34 56 78',
  birthDate: DateTime(1990, 5, 15),
  birthPlace: 'Paris',
  nationality: 'Française',
  profession: 'Ingénieure',
  employer: 'Tech Corp',
  monthlyIncomeCents: 350000,
  previousAddress: '5 rue Ancienne, 75001 Paris',
  guarantorName: 'Pierre Martin',
  guarantorEmail: 'pierre.martin@test.com',
  guarantorPhone: '06 98 76 54 32',
  createdAt: DateTime.utc(2024, 6, 1),
  updatedAt: DateTime.utc(2024, 6, 2),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Tenant — backward compat (champs optionnels absents)', () {
    test(
      'désérialisation sans les nouveaux champs ne lève pas d\'exception',
      () {
        final json = <String, dynamic>{
          'id': 't-legacy',
          'landlord_id': 'owner',
          'first_name': 'Jean',
          'last_name': 'Dupont',
          'email': 'jean@test.com',
          'created_at': '2023-01-01T00:00:00.000Z',
          'updated_at': '2023-01-01T00:00:00.000Z',
        };

        expect(() => Tenant.fromJson(json), returnsNormally);
      },
    );

    test('les nouveaux champs sont null par défaut (tenant legacy)', () {
      final json = <String, dynamic>{
        'id': 't-legacy',
        'landlord_id': 'owner',
        'first_name': 'Jean',
        'last_name': 'Dupont',
        'email': 'jean@test.com',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      };

      final t = Tenant.fromJson(json);
      expect(t.birthDate, isNull);
      expect(t.birthPlace, isNull);
      expect(t.nationality, isNull);
      expect(t.profession, isNull);
      expect(t.employer, isNull);
      expect(t.monthlyIncomeCents, isNull);
      expect(t.previousAddress, isNull);
      expect(t.guarantorName, isNull);
      expect(t.guarantorEmail, isNull);
      expect(t.guarantorPhone, isNull);
    });

    test('phone null par défaut si absent du JSON', () {
      final json = <String, dynamic>{
        'id': 't-legacy',
        'landlord_id': 'owner',
        'first_name': 'Jean',
        'last_name': 'Dupont',
        'email': 'jean@test.com',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      };

      final t = Tenant.fromJson(json);
      expect(t.phone, isNull);
    });
  });

  group('Tenant — round-trip JSON (minimal)', () {
    test('toJson puis fromJson restitue les champs obligatoires', () {
      final original = _minimalTenant();
      final restored = Tenant.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.firstName, original.firstName);
      expect(restored.lastName, original.lastName);
      expect(restored.email, original.email);
    });

    test('les nouveaux champs sont null dans le round-trip minimal', () {
      final original = _minimalTenant();
      final restored = Tenant.fromJson(original.toJson());

      expect(restored.birthDate, isNull);
      expect(restored.monthlyIncomeCents, isNull);
      expect(restored.guarantorName, isNull);
    });
  });

  group('Tenant — round-trip JSON (complet)', () {
    test('toJson puis fromJson restitue tous les nouveaux champs', () {
      final original = _fullTenant();
      final restored = Tenant.fromJson(original.toJson());

      expect(restored.phone, '06 12 34 56 78');
      expect(restored.birthDate?.year, 1990);
      expect(restored.birthDate?.month, 5);
      expect(restored.birthDate?.day, 15);
      expect(restored.birthPlace, 'Paris');
      expect(restored.nationality, 'Française');
      expect(restored.profession, 'Ingénieure');
      expect(restored.employer, 'Tech Corp');
      expect(restored.monthlyIncomeCents, 350000);
      expect(restored.previousAddress, '5 rue Ancienne, 75001 Paris');
      expect(restored.guarantorName, 'Pierre Martin');
      expect(restored.guarantorEmail, 'pierre.martin@test.com');
      expect(restored.guarantorPhone, '06 98 76 54 32');
    });

    test('birth_date est sérialisée en ISO YYYY-MM-DD', () {
      final json = _fullTenant().toJson();
      expect(json['birth_date'], '1990-05-15');
    });

    test('birth_date null → null dans le JSON', () {
      final json = _minimalTenant().toJson();
      expect(json['birth_date'], isNull);
    });

    test('monthly_income_cents est sérialisé en int', () {
      final json = _fullTenant().toJson();
      expect(json['monthly_income_cents'], 350000);
    });
  });

  group('Tenant — désérialisation birth_date depuis JSON', () {
    test('birth_date "1990-05-15" → DateTime(1990, 5, 15)', () {
      final json = <String, dynamic>{
        'id': 't-3',
        'landlord_id': 'owner',
        'first_name': 'Test',
        'last_name': 'User',
        'email': 'test@test.com',
        'birth_date': '1990-05-15',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final t = Tenant.fromJson(json);
      expect(t.birthDate?.year, 1990);
      expect(t.birthDate?.month, 5);
      expect(t.birthDate?.day, 15);
    });

    test('birth_date null → birthDate null', () {
      final json = <String, dynamic>{
        'id': 't-4',
        'landlord_id': 'owner',
        'first_name': 'Test',
        'last_name': 'User',
        'email': 'test@test.com',
        'birth_date': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final t = Tenant.fromJson(json);
      expect(t.birthDate, isNull);
    });

    test('birth_date "1900-01-01" (limite min) → round-trip exact', () {
      final json = <String, dynamic>{
        'id': 't-5',
        'landlord_id': 'owner',
        'first_name': 'Test',
        'last_name': 'User',
        'email': 'test@test.com',
        'birth_date': '1900-01-01',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final t = Tenant.fromJson(json);
      expect(t.birthDate?.year, 1900);
      expect(t.birthDate?.month, 1);
      expect(t.birthDate?.day, 1);
      // Re-sérialisation.
      expect(t.toJson()['birth_date'], '1900-01-01');
    });
  });
}
