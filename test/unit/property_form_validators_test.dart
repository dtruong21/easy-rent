import 'package:easyrent/core/utils/property_form_validators.dart';
import 'package:easyrent/core/validation/validation_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PropertyFormValidators.validateName', () {
    test('null retourne message erreur', () {
      expect(PropertyFormValidators.validateName(null), isNotNull);
    });

    test('vide retourne message erreur', () {
      expect(PropertyFormValidators.validateName(''), isNotNull);
    });

    test('espaces seuls retourne message erreur', () {
      expect(PropertyFormValidators.validateName('   '), isNotNull);
    });

    test('valeur valide retourne null', () {
      expect(PropertyFormValidators.validateName('Appartement Lyon'), isNull);
    });

    test('vide retourne ValidationError.propertyNameRequired', () {
      expect(
        PropertyFormValidators.validateName(''),
        ValidationError.propertyNameRequired,
      );
    });

    test('valeur avec espaces autour retourne null (trim implicite)', () {
      expect(PropertyFormValidators.validateName('  Mon bien  '), isNull);
    });
  });

  group('PropertyFormValidators.validateAddress', () {
    test('null retourne message erreur', () {
      expect(PropertyFormValidators.validateAddress(null), isNotNull);
    });

    test('vide retourne message erreur', () {
      expect(PropertyFormValidators.validateAddress(''), isNotNull);
    });

    test('espaces seuls retourne message erreur', () {
      expect(PropertyFormValidators.validateAddress('   '), isNotNull);
    });

    test('valeur valide retourne null', () {
      expect(
        PropertyFormValidators.validateAddress(
          '12 rue de la Paix, 75001 Paris',
        ),
        isNull,
      );
    });

    test('vide retourne ValidationError.propertyAddressRequired', () {
      expect(
        PropertyFormValidators.validateAddress(''),
        ValidationError.propertyAddressRequired,
      );
    });
  });

  group('PropertyFormValidators.validatePostalCode', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validatePostalCode(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validatePostalCode(''), isNull);
    });

    test('5 chiffres valides retourne null', () {
      expect(PropertyFormValidators.validatePostalCode('75001'), isNull);
    });

    test('4 chiffres retourne erreur', () {
      expect(PropertyFormValidators.validatePostalCode('7500'), isNotNull);
    });

    test('6 chiffres retourne erreur', () {
      expect(PropertyFormValidators.validatePostalCode('750011'), isNotNull);
    });

    test('lettres retournent erreur', () {
      expect(PropertyFormValidators.validatePostalCode('ABCDE'), isNotNull);
    });

    test('code postal avec espaces (valide après trim) retourne null', () {
      expect(PropertyFormValidators.validatePostalCode(' 75001 '), isNull);
    });
  });

  group('PropertyFormValidators.validateRooms', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateRooms(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateRooms(''), isNull);
    });

    test('1 retourne null', () {
      expect(PropertyFormValidators.validateRooms('1'), isNull);
    });

    test('50 retourne null', () {
      expect(PropertyFormValidators.validateRooms('50'), isNull);
    });

    test('0 retourne erreur', () {
      expect(PropertyFormValidators.validateRooms('0'), isNotNull);
    });

    test('51 retourne erreur', () {
      expect(PropertyFormValidators.validateRooms('51'), isNotNull);
    });

    test('texte non numérique retourne erreur', () {
      expect(PropertyFormValidators.validateRooms('abc'), isNotNull);
    });
  });

  group('PropertyFormValidators.validateBedrooms', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateBedrooms(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateBedrooms(''), isNull);
    });

    test('0 retourne null (studio sans chambre)', () {
      expect(PropertyFormValidators.validateBedrooms('0'), isNull);
    });

    test('50 retourne null', () {
      expect(PropertyFormValidators.validateBedrooms('50'), isNull);
    });

    test('-1 retourne erreur', () {
      expect(PropertyFormValidators.validateBedrooms('-1'), isNotNull);
    });

    test('51 retourne erreur', () {
      expect(PropertyFormValidators.validateBedrooms('51'), isNotNull);
    });
  });

  group('PropertyFormValidators.validateFloor', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateFloor(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateFloor(''), isNull);
    });

    test('0 retourne null (RDC)', () {
      expect(PropertyFormValidators.validateFloor('0'), isNull);
    });

    test('-5 retourne null (sous-sol extrême)', () {
      expect(PropertyFormValidators.validateFloor('-5'), isNull);
    });

    test('200 retourne null', () {
      expect(PropertyFormValidators.validateFloor('200'), isNull);
    });

    test('-6 retourne erreur', () {
      expect(PropertyFormValidators.validateFloor('-6'), isNotNull);
    });

    test('201 retourne erreur', () {
      expect(PropertyFormValidators.validateFloor('201'), isNotNull);
    });
  });

  group('PropertyFormValidators.validateConstructionYear', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateConstructionYear(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateConstructionYear(''), isNull);
    });

    test('1700 retourne null (borne inférieure)', () {
      expect(PropertyFormValidators.validateConstructionYear('1700'), isNull);
    });

    test('2024 retourne null', () {
      expect(PropertyFormValidators.validateConstructionYear('2024'), isNull);
    });

    test('1699 retourne erreur', () {
      expect(
        PropertyFormValidators.validateConstructionYear('1699'),
        isNotNull,
      );
    });

    test('année trop élevée (now+2) retourne erreur', () {
      final tooFar = (DateTime.now().year + 2).toString();
      expect(
        PropertyFormValidators.validateConstructionYear(tooFar),
        isNotNull,
      );
    });
  });

  group('PropertyFormValidators.validateDpeLetter', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateDpeLetter(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateDpeLetter(''), isNull);
    });

    test('"A" retourne null', () {
      expect(PropertyFormValidators.validateDpeLetter('A'), isNull);
    });

    test('"G" retourne null', () {
      expect(PropertyFormValidators.validateDpeLetter('G'), isNull);
    });

    test('"H" retourne erreur', () {
      expect(PropertyFormValidators.validateDpeLetter('H'), isNotNull);
    });

    test('"a" (minuscule) retourne null (toUpperCase)', () {
      expect(PropertyFormValidators.validateDpeLetter('a'), isNull);
    });

    test('"AB" retourne erreur', () {
      expect(PropertyFormValidators.validateDpeLetter('AB'), isNotNull);
    });
  });

  group('PropertyFormValidators.validateDpeValue', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateDpeValue(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateDpeValue(''), isNull);
    });

    test('1 retourne null (borne inférieure)', () {
      expect(PropertyFormValidators.validateDpeValue('1'), isNull);
    });

    test('1999 retourne null (borne supérieure)', () {
      expect(PropertyFormValidators.validateDpeValue('1999'), isNull);
    });

    test('0 retourne erreur', () {
      expect(PropertyFormValidators.validateDpeValue('0'), isNotNull);
    });

    test('2000 retourne erreur', () {
      expect(PropertyFormValidators.validateDpeValue('2000'), isNotNull);
    });
  });

  group('PropertyFormValidators.validateGesLetter', () {
    test('null retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateGesLetter(null), isNull);
    });

    test('vide retourne null (optionnel)', () {
      expect(PropertyFormValidators.validateGesLetter(''), isNull);
    });

    test('"A" retourne null', () {
      expect(PropertyFormValidators.validateGesLetter('A'), isNull);
    });

    test('"G" retourne null', () {
      expect(PropertyFormValidators.validateGesLetter('G'), isNull);
    });

    test('"Z" retourne erreur', () {
      expect(PropertyFormValidators.validateGesLetter('Z'), isNotNull);
    });

    test('"g" (minuscule) retourne null (toUpperCase)', () {
      expect(PropertyFormValidators.validateGesLetter('g'), isNull);
    });
  });
}
