import 'package:easyrent/core/utils/password_validator.dart';
import 'package:easyrent/features/auth/domain/auth_error.dart';
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
      test('null → AuthError.passwordRequired', () {
        expect(PasswordValidator.validate(null), AuthError.passwordRequired);
      });

      test('chaîne vide → AuthError.passwordRequired', () {
        expect(PasswordValidator.validate(''), AuthError.passwordRequired);
      });
    });

    group('invalide — trop court', () {
      final shortPasswords = ['a1', 'Ab1', '1234567', 'abcdefg'];
      for (final pw in shortPasswords) {
        test('"$pw" (${pw.length} chars) → AuthError.passwordTooShort', () {
          expect(PasswordValidator.validate(pw), AuthError.passwordTooShort);
        });
      }
    });

    group('invalide — pas de lettre', () {
      test('chiffres seuls → AuthError.passwordMissingLetter', () {
        expect(
          PasswordValidator.validate('12345678'),
          AuthError.passwordMissingLetter,
        );
      });
      test('chiffres + symboles seuls → AuthError.passwordMissingLetter', () {
        expect(
          PasswordValidator.validate('1234!@#%'),
          AuthError.passwordMissingLetter,
        );
      });
    });

    group('invalide — pas de chiffre', () {
      test('lettres seules → AuthError.passwordMissingDigit', () {
        expect(
          PasswordValidator.validate('abcdefgh'),
          AuthError.passwordMissingDigit,
        );
      });
      test('lettres + symboles → AuthError.passwordMissingDigit', () {
        expect(
          PasswordValidator.validate('abcd!@#%'),
          AuthError.passwordMissingDigit,
        );
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
        expect(
          PasswordValidator.validate('abcde1f'),
          AuthError.passwordTooShort,
        );
      });

      test(
        'mot de passe purement avec accents sans lettre ASCII → invalide',
        () {
          // Les lettres accentuées seules ne satisfont pas [a-zA-Z] — cohérent
          // avec la contrainte Firebase Auth qui requiert a-z ou A-Z.
          expect(
            PasswordValidator.validate('éàü12345'),
            AuthError.passwordMissingLetter,
          );
        },
      );

      test('mot de passe avec espaces (valide si critères remplis)', () {
        expect(PasswordValidator.validate('ab cde 1f'), isNull);
      });
    });
  });
}
