import 'package:easyrent/core/utils/property_form_validators.dart';
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

    test('message erreur contient "nom"', () {
      final msg = PropertyFormValidators.validateName('');
      expect(msg, isNotNull);
      expect(msg!.toLowerCase(), contains('nom'));
    });

    test('valeur avec espaces autour retourne null (trim implicite)', () {
      // Le champ envoie la valeur brute — le validateur doit trimmer.
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

    test('message erreur contient "adresse"', () {
      final msg = PropertyFormValidators.validateAddress('');
      expect(msg, isNotNull);
      expect(msg!.toLowerCase(), contains('adresse'));
    });
  });
}
