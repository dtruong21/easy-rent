/// Tests unitaires de [LeaseFormValidators].
library;

import 'package:easyrent/core/utils/lease_form_validators.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:flutter_test/flutter_test.dart';

Property _fakeProperty() => Property(
  id: 'p1',
  landlordId: 'lld',
  name: 'Appart',
  address: '1 rue Test',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Tenant _fakeTenant() => Tenant(
  id: 't1',
  landlordId: 'lld',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean@test.com',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  group('validateProperty', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateProperty(null), isNotNull);
    });

    test('property sélectionnée → null', () {
      expect(LeaseFormValidators.validateProperty(_fakeProperty()), isNull);
    });
  });

  group('validateTenant', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateTenant(null), isNotNull);
    });

    test('tenant sélectionné → null', () {
      expect(LeaseFormValidators.validateTenant(_fakeTenant()), isNull);
    });
  });

  group('validateRentAmount', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateRentAmount(null), isNotNull);
    });

    test('vide → erreur', () {
      expect(LeaseFormValidators.validateRentAmount(''), isNotNull);
    });

    test('"0" → erreur (doit être > 0)', () {
      expect(LeaseFormValidators.validateRentAmount('0'), isNotNull);
    });

    test('négatif "-100" → erreur', () {
      expect(LeaseFormValidators.validateRentAmount('-100'), isNotNull);
    });

    test('"abc" → erreur', () {
      expect(LeaseFormValidators.validateRentAmount('abc'), isNotNull);
    });

    test('"850" → null', () {
      expect(LeaseFormValidators.validateRentAmount('850'), isNull);
    });

    test('"850,00" (virgule) → null', () {
      expect(LeaseFormValidators.validateRentAmount('850,00'), isNull);
    });

    test('"0.01" → null (centimes positifs)', () {
      expect(LeaseFormValidators.validateRentAmount('0.01'), isNull);
    });
  });

  group('validateChargesAmount', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount(null), isNotNull);
    });

    test('vide → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount(''), isNotNull);
    });

    test('"0" → null (zéro accepté)', () {
      expect(LeaseFormValidators.validateChargesAmount('0'), isNull);
    });

    test('"50,00" → null', () {
      expect(LeaseFormValidators.validateChargesAmount('50,00'), isNull);
    });

    test('négatif "-10" → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount('-10'), isNotNull);
    });

    test('"abc" → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount('abc'), isNotNull);
    });
  });

  group('validateStartDate', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateStartDate(null), isNotNull);
    });

    test('date fournie → null', () {
      expect(
        LeaseFormValidators.validateStartDate(DateTime(2024, 1, 1)),
        isNull,
      );
    });
  });

  group('validateEndDate', () {
    test('endDate null → null (CDI)', () {
      expect(
        LeaseFormValidators.validateEndDate(null, DateTime(2024, 1, 1)),
        isNull,
      );
    });

    test('endDate > startDate → null', () {
      expect(
        LeaseFormValidators.validateEndDate(
          DateTime(2024, 12, 31),
          DateTime(2024, 1, 1),
        ),
        isNull,
      );
    });

    test('endDate == startDate → erreur', () {
      final date = DateTime(2024, 6, 1);
      expect(LeaseFormValidators.validateEndDate(date, date), isNotNull);
    });

    test('endDate < startDate → erreur', () {
      expect(
        LeaseFormValidators.validateEndDate(
          DateTime(2024, 1, 1),
          DateTime(2024, 12, 31),
        ),
        isNotNull,
      );
    });

    test('endDate fournie mais startDate null → null (pas de cross-check)', () {
      expect(
        LeaseFormValidators.validateEndDate(DateTime(2024, 6), null),
        isNull,
      );
    });
  });
}
