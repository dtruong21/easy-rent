import 'package:easyrent/core/utils/email_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmailValidator', () {
    group('isValid — cas valides', () {
      final validEmails = [
        'user@example.com',
        'user+tag@example.fr',
        'user.name@sub.domain.org',
        'USER@EXAMPLE.COM',
        'first.last@company.io',
        'a@b.cc',
      ];

      for (final email in validEmails) {
        test('accepte "$email"', () {
          expect(EmailValidator.isValid(email), isTrue);
        });
      }
    });

    group('isValid — cas invalides', () {
      final invalidEmails = [
        '',
        '   ',
        'notanemail',
        '@nodomain.com',
        'user@',
        'user@.com',
        'user name@example.com',
        'user@@example.com',
        'user@example',
      ];

      for (final email in invalidEmails) {
        test('rejette "$email"', () {
          expect(EmailValidator.isValid(email), isFalse);
        });
      }
    });

    test('ignore les espaces en tête et queue', () {
      // EmailValidator.isValid trimme avant de valider.
      expect(EmailValidator.isValid('  user@example.com  '), isTrue);
    });
  });
}
