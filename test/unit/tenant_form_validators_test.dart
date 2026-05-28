import 'package:easyrent/core/utils/tenant_form_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TenantFormValidators', () {
    // -----------------------------------------------------------------------
    // validateFirstName
    // -----------------------------------------------------------------------
    group('validateFirstName', () {
      test('null → erreur obligatoire', () {
        expect(TenantFormValidators.validateFirstName(null), isNotNull);
      });

      test('chaîne vide → erreur obligatoire', () {
        expect(TenantFormValidators.validateFirstName(''), isNotNull);
      });

      test('espaces uniquement → erreur obligatoire', () {
        expect(TenantFormValidators.validateFirstName('   '), isNotNull);
      });

      test('valeur valide → null', () {
        expect(TenantFormValidators.validateFirstName('Jean'), isNull);
      });

      test('valeur avec espaces autour → null (trimmed)', () {
        expect(TenantFormValidators.validateFirstName('  Marie  '), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // validateLastName
    // -----------------------------------------------------------------------
    group('validateLastName', () {
      test('null → erreur obligatoire', () {
        expect(TenantFormValidators.validateLastName(null), isNotNull);
      });

      test('chaîne vide → erreur obligatoire', () {
        expect(TenantFormValidators.validateLastName(''), isNotNull);
      });

      test('espaces uniquement → erreur obligatoire', () {
        expect(TenantFormValidators.validateLastName('   '), isNotNull);
      });

      test('valeur valide → null', () {
        expect(TenantFormValidators.validateLastName('Dupont'), isNull);
      });

      test('valeur avec espaces autour → null (trimmed)', () {
        expect(TenantFormValidators.validateLastName('  Martin  '), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // validateEmail
    // -----------------------------------------------------------------------
    group('validateEmail', () {
      test('null → erreur obligatoire', () {
        expect(TenantFormValidators.validateEmail(null), isNotNull);
      });

      test('chaîne vide → erreur obligatoire', () {
        expect(TenantFormValidators.validateEmail(''), isNotNull);
      });

      test('espaces uniquement → erreur obligatoire', () {
        expect(TenantFormValidators.validateEmail('   '), isNotNull);
      });

      test('format invalide — sans @  → erreur format', () {
        expect(TenantFormValidators.validateEmail('jean.dupont.fr'), isNotNull);
      });

      test('format invalide — sans domaine → erreur format', () {
        expect(TenantFormValidators.validateEmail('jean@'), isNotNull);
      });

      test('format invalide — sans TLD → erreur format', () {
        expect(TenantFormValidators.validateEmail('jean@domaine'), isNotNull);
      });

      test('format valide → null', () {
        expect(
          TenantFormValidators.validateEmail('jean.dupont@email.com'),
          isNull,
        );
      });

      test('format valide avec + et tiret → null', () {
        expect(
          TenantFormValidators.validateEmail('jean+test@mon-email.fr'),
          isNull,
        );
      });

      test('format valide avec espaces autour → null (trimmed)', () {
        expect(
          TenantFormValidators.validateEmail('  test@example.com  '),
          isNull,
        );
      });
    });

    // -----------------------------------------------------------------------
    // validatePhone
    // -----------------------------------------------------------------------
    group('validatePhone', () {
      test('null → null (V1 : toujours valide)', () {
        expect(TenantFormValidators.validatePhone(null), isNull);
      });

      test('chaîne vide → null (optionnel)', () {
        expect(TenantFormValidators.validatePhone(''), isNull);
      });

      test('format FR → null (V1 : string libre)', () {
        expect(TenantFormValidators.validatePhone('06 12 34 56 78'), isNull);
      });

      test('format international → null (V1 : string libre)', () {
        expect(TenantFormValidators.validatePhone('+33 6 12 34 56 78'), isNull);
      });

      test('texte quelconque → null (V1 : string libre)', () {
        expect(TenantFormValidators.validatePhone('pas un tel'), isNull);
      });
    });
  });
}
