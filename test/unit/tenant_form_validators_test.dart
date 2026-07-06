import 'package:easyrent/core/utils/tenant_form_validators.dart';
import 'package:easyrent/core/validation/validation_error.dart';
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
    // validateEmailError — pilote FEAT-043 (i18n) : ValidationError pur, sans
    // BuildContext ni message FR en dur (voir lib/l10n/l10n_convention.dart).
    // -----------------------------------------------------------------------
    group('validateEmailError', () {
      test('null → ValidationError.required', () {
        expect(
          TenantFormValidators.validateEmailError(null),
          ValidationError.required,
        );
      });

      test('chaîne vide → ValidationError.required', () {
        expect(
          TenantFormValidators.validateEmailError(''),
          ValidationError.required,
        );
      });

      test('format invalide → ValidationError.invalidEmail', () {
        expect(
          TenantFormValidators.validateEmailError('pas-un-email'),
          ValidationError.invalidEmail,
        );
      });

      test('format valide → null', () {
        expect(
          TenantFormValidators.validateEmailError('jean.dupont@email.com'),
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

    // -----------------------------------------------------------------------
    // validateBirthDate
    // -----------------------------------------------------------------------
    group('validateBirthDate', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateBirthDate(null), isNull);
      });

      test('date valide (adulte 30 ans) → null', () {
        final now = DateTime.now();
        final birthDate = DateTime(now.year - 30, now.month, now.day);
        expect(TenantFormValidators.validateBirthDate(birthDate), isNull);
      });

      test('date limite min (1900-01-01) → null', () {
        expect(
          TenantFormValidators.validateBirthDate(DateTime(1900, 1, 1)),
          isNull,
        );
      });

      test('date avant 1900 → erreur', () {
        expect(
          TenantFormValidators.validateBirthDate(DateTime(1899, 12, 31)),
          isNotNull,
        );
      });

      test('âge exactement 18 ans → null', () {
        final now = DateTime.now();
        final exactly18 = DateTime(now.year - 18, now.month, now.day);
        expect(TenantFormValidators.validateBirthDate(exactly18), isNull);
      });

      test('âge < 18 ans (17 ans) → erreur', () {
        final now = DateTime.now();
        final under18 = DateTime(now.year - 17, now.month, now.day);
        expect(TenantFormValidators.validateBirthDate(under18), isNotNull);
      });

      test('date future → erreur (âge négatif)', () {
        final future = DateTime.now().add(const Duration(days: 365));
        expect(TenantFormValidators.validateBirthDate(future), isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // validateBirthPlace
    // -----------------------------------------------------------------------
    group('validateBirthPlace', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateBirthPlace(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validateBirthPlace(''), isNull);
      });

      test('valeur courte → null', () {
        expect(TenantFormValidators.validateBirthPlace('Paris'), isNull);
      });

      test('exactement 100 chars → null', () {
        expect(TenantFormValidators.validateBirthPlace('a' * 100), isNull);
      });

      test('101 chars → erreur', () {
        expect(TenantFormValidators.validateBirthPlace('a' * 101), isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // validateNationality
    // -----------------------------------------------------------------------
    group('validateNationality', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateNationality(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validateNationality(''), isNull);
      });

      test('valeur courte → null', () {
        expect(TenantFormValidators.validateNationality('Française'), isNull);
      });

      test('exactement 60 chars → null', () {
        expect(TenantFormValidators.validateNationality('a' * 60), isNull);
      });

      test('61 chars → erreur', () {
        expect(TenantFormValidators.validateNationality('a' * 61), isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // validateProfession
    // -----------------------------------------------------------------------
    group('validateProfession', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateProfession(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validateProfession(''), isNull);
      });

      test('valeur courte → null', () {
        expect(TenantFormValidators.validateProfession('Ingénieur'), isNull);
      });

      test('exactement 100 chars → null', () {
        expect(TenantFormValidators.validateProfession('a' * 100), isNull);
      });

      test('101 chars → erreur', () {
        expect(TenantFormValidators.validateProfession('a' * 101), isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // validateEmployer
    // -----------------------------------------------------------------------
    group('validateEmployer', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateEmployer(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validateEmployer(''), isNull);
      });

      test('valeur courte → null', () {
        expect(TenantFormValidators.validateEmployer('Tech Corp'), isNull);
      });

      test('101 chars → erreur', () {
        expect(TenantFormValidators.validateEmployer('a' * 101), isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // validateMonthlyIncomeCents
    // -----------------------------------------------------------------------
    group('validateMonthlyIncomeCents', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateMonthlyIncomeCents(null), isNull);
      });

      test('0 → null (minimum)', () {
        expect(TenantFormValidators.validateMonthlyIncomeCents(0), isNull);
      });

      test('valeur positive normale → null', () {
        expect(TenantFormValidators.validateMonthlyIncomeCents(250000), isNull);
      });

      test('borne max (10_000_000_000) → null', () {
        expect(
          TenantFormValidators.validateMonthlyIncomeCents(10000000000),
          isNull,
        );
      });

      test('négatif → erreur', () {
        expect(TenantFormValidators.validateMonthlyIncomeCents(-1), isNotNull);
      });

      test('au-dessus de 10G → erreur', () {
        expect(
          TenantFormValidators.validateMonthlyIncomeCents(10000000001),
          isNotNull,
        );
      });
    });

    // -----------------------------------------------------------------------
    // validatePreviousAddress
    // -----------------------------------------------------------------------
    group('validatePreviousAddress', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validatePreviousAddress(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validatePreviousAddress(''), isNull);
      });

      test('valeur courte → null', () {
        expect(
          TenantFormValidators.validatePreviousAddress('1 rue des Fleurs'),
          isNull,
        );
      });

      test('exactement 300 chars → null', () {
        expect(TenantFormValidators.validatePreviousAddress('a' * 300), isNull);
      });

      test('301 chars → erreur', () {
        expect(
          TenantFormValidators.validatePreviousAddress('a' * 301),
          isNotNull,
        );
      });
    });

    // -----------------------------------------------------------------------
    // validateGuarantorName
    // -----------------------------------------------------------------------
    group('validateGuarantorName', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateGuarantorName(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validateGuarantorName(''), isNull);
      });

      test('valeur courte → null', () {
        expect(
          TenantFormValidators.validateGuarantorName('Pierre Martin'),
          isNull,
        );
      });

      test('exactement 200 chars → null', () {
        expect(TenantFormValidators.validateGuarantorName('a' * 200), isNull);
      });

      test('201 chars → erreur', () {
        expect(
          TenantFormValidators.validateGuarantorName('a' * 201),
          isNotNull,
        );
      });
    });

    // -----------------------------------------------------------------------
    // validateGuarantorEmail
    // -----------------------------------------------------------------------
    group('validateGuarantorEmail', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateGuarantorEmail(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validateGuarantorEmail(''), isNull);
      });

      test('format valide → null', () {
        expect(
          TenantFormValidators.validateGuarantorEmail('garant@test.fr'),
          isNull,
        );
      });

      test('format invalide (sans @) → erreur', () {
        expect(
          TenantFormValidators.validateGuarantorEmail('garant.test.fr'),
          isNotNull,
        );
      });

      test('format invalide (sans TLD) → erreur', () {
        expect(
          TenantFormValidators.validateGuarantorEmail('garant@domaine'),
          isNotNull,
        );
      });
    });

    // -----------------------------------------------------------------------
    // validateGuarantorPhone
    // -----------------------------------------------------------------------
    group('validateGuarantorPhone', () {
      test('null → null (optionnel)', () {
        expect(TenantFormValidators.validateGuarantorPhone(null), isNull);
      });

      test('vide → null (optionnel)', () {
        expect(TenantFormValidators.validateGuarantorPhone(''), isNull);
      });

      test('format FR → null', () {
        expect(
          TenantFormValidators.validateGuarantorPhone('06 12 34 56 78'),
          isNull,
        );
      });

      test('exactement 30 chars → null', () {
        expect(TenantFormValidators.validateGuarantorPhone('a' * 30), isNull);
      });

      test('31 chars → erreur', () {
        expect(
          TenantFormValidators.validateGuarantorPhone('a' * 31),
          isNotNull,
        );
      });
    });
  });
}
