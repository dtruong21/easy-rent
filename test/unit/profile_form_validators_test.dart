/// Tests unitaires des validateurs du formulaire profil bailleur.
///
/// Logique pure — aucune dépendance Flutter ou Supabase.
library;

import 'package:easyrent/core/utils/profile_form_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // validateFullName
  // ---------------------------------------------------------------------------
  group('validateFullName', () {
    test('null → erreur obligatoire', () {
      expect(ProfileFormValidators.validateFullName(null), isNotNull);
    });

    test('vide → erreur obligatoire', () {
      expect(ProfileFormValidators.validateFullName(''), isNotNull);
    });

    test('espaces seuls → erreur obligatoire', () {
      expect(ProfileFormValidators.validateFullName('   '), isNotNull);
    });

    test('1 caractère → erreur longueur min', () {
      expect(ProfileFormValidators.validateFullName('A'), isNotNull);
    });

    test('2 caractères → valide', () {
      expect(ProfileFormValidators.validateFullName('AB'), isNull);
    });

    test('nom normal → valide', () {
      expect(ProfileFormValidators.validateFullName('Jean Dupont'), isNull);
    });

    test('200 caractères → valide', () {
      expect(ProfileFormValidators.validateFullName('A' * 200), isNull);
    });

    test('201 caractères → erreur longueur max', () {
      expect(ProfileFormValidators.validateFullName('A' * 201), isNotNull);
    });

    test('message contient "obligatoire" si vide', () {
      final msg = ProfileFormValidators.validateFullName('');
      expect(msg, contains('obligatoire'));
    });
  });

  // ---------------------------------------------------------------------------
  // validateAddress
  // ---------------------------------------------------------------------------
  group('validateAddress', () {
    test('null → erreur obligatoire', () {
      expect(ProfileFormValidators.validateAddress(null), isNotNull);
    });

    test('vide → erreur obligatoire', () {
      expect(ProfileFormValidators.validateAddress(''), isNotNull);
    });

    test('espaces seuls → erreur obligatoire', () {
      expect(ProfileFormValidators.validateAddress('   '), isNotNull);
    });

    test('4 caractères → erreur longueur min', () {
      expect(ProfileFormValidators.validateAddress('1234'), isNotNull);
    });

    test('5 caractères → valide', () {
      expect(ProfileFormValidators.validateAddress('12345'), isNull);
    });

    test('adresse normale → valide', () {
      expect(
        ProfileFormValidators.validateAddress('12 rue de la Paix\n75001 Paris'),
        isNull,
      );
    });

    test('500 caractères → valide', () {
      expect(ProfileFormValidators.validateAddress('A' * 500), isNull);
    });

    test('501 caractères → erreur longueur max', () {
      expect(ProfileFormValidators.validateAddress('A' * 501), isNotNull);
    });

    test('message contient "obligatoire" si vide', () {
      final msg = ProfileFormValidators.validateAddress('');
      expect(msg, contains('obligatoire'));
    });
  });

  // ---------------------------------------------------------------------------
  // validatePhone
  // ---------------------------------------------------------------------------
  group('validatePhone', () {
    test('null → null (optionnel)', () {
      expect(ProfileFormValidators.validatePhone(null), isNull);
    });

    test('vide → null (optionnel)', () {
      expect(ProfileFormValidators.validatePhone(''), isNull);
    });

    test('espaces seuls → null (optionnel)', () {
      expect(ProfileFormValidators.validatePhone('   '), isNull);
    });

    test('numéro FR standard → valide', () {
      expect(ProfileFormValidators.validatePhone('06 12 34 56 78'), isNull);
    });

    test('numéro international → valide', () {
      expect(ProfileFormValidators.validatePhone('+33612345678'), isNull);
    });

    test('numéro avec points → valide', () {
      expect(ProfileFormValidators.validatePhone('06.12.34.56.78'), isNull);
    });

    test('5 caractères → erreur (trop court)', () {
      expect(ProfileFormValidators.validatePhone('12345'), isNotNull);
    });

    test('lettres → erreur (format invalide)', () {
      expect(ProfileFormValidators.validatePhone('abc def'), isNotNull);
    });

    test('21 caractères avec chiffres → erreur (trop long)', () {
      expect(ProfileFormValidators.validatePhone('1' * 21), isNotNull);
    });
  });
}
