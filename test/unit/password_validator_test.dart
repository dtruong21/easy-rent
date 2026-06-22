import 'package:easyrent/core/utils/password_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordValidator', () {
    group('valide', () {
      final validPasswords = [
        'abcdef1g',
        'Password1',
        'abc12345',
        'a1b2c3d4',
        'test1234',
        'ABCD1234',
        'azerty42',
        'motdepasse1',
        'Abc12345',
      ];
      for (final pw in validPasswords) {
        test('"$pw" est valide', () {
          expect(PasswordValidator.validate(pw), isNull);
        });
      }
    });

    group('invalide — vide ou null', () {
      test('null → "Mot de passe requis"', () {
        expect(PasswordValidator.validate(null), 'Mot de passe requis');
      });

      test('chaîne vide → "Mot de passe requis"', () {
        expect(PasswordValidator.validate(''), 'Mot de passe requis');
      });
    });

    group('invalide — trop court', () {
      final shortPasswords = ['a1', 'Ab1', '1234567', 'abcdefg'];
      for (final pw in shortPasswords) {
        test('"$pw" (${pw.length} chars) → "8 caractères minimum"', () {
          expect(PasswordValidator.validate(pw), '8 caractères minimum');
        });
      }
    });

    group('invalide — pas de lettre', () {
      test('chiffres seuls → "Au moins une lettre"', () {
        expect(PasswordValidator.validate('12345678'), 'Au moins une lettre');
      });
      test('chiffres + symboles seuls → "Au moins une lettre"', () {
        expect(PasswordValidator.validate('1234!@#%'), 'Au moins une lettre');
      });
    });

    group('invalide — pas de chiffre', () {
      test('lettres seules → "Au moins un chiffre"', () {
        expect(PasswordValidator.validate('abcdefgh'), 'Au moins un chiffre');
      });
      test('lettres + symboles → "Au moins un chiffre"', () {
        expect(PasswordValidator.validate('abcd!@#%'), 'Au moins un chiffre');
      });
    });

    group('cas limites', () {
      test('minLength constant vaut 8', () {
        expect(PasswordValidator.minLength, 8);
      });

      test('exactement 8 chars avec lettre+chiffre → valide', () {
        expect(PasswordValidator.validate('abcde1fg'), isNull);
      });

      test('exactement 7 chars → trop court', () {
        expect(PasswordValidator.validate('abcde1f'), '8 caractères minimum');
      });

      test(
        'mot de passe purement avec accents sans lettre ASCII → invalide',
        () {
          // Les lettres accentuées seules ne satisfont pas [a-zA-Z] — cohérent
          // avec la contrainte Supabase qui requiert a-z ou A-Z.
          expect(PasswordValidator.validate('éàü12345'), 'Au moins une lettre');
        },
      );

      test('mot de passe avec espaces (valide si critères remplis)', () {
        expect(PasswordValidator.validate('ab cde 1f'), isNull);
      });
    });
  });
}
