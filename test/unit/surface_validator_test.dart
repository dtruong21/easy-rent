import 'package:easyrent/core/utils/surface_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SurfaceValidator.parse', () {
    // -------------------------------------------------------------------------
    // Vide — valide (champ optionnel)
    // -------------------------------------------------------------------------
    test('vide retourne null (champ optionnel)', () {
      expect(SurfaceValidator.parse(''), isNull);
    });

    test('espaces seuls retourne null', () {
      expect(SurfaceValidator.parse('   '), isNull);
    });

    // -------------------------------------------------------------------------
    // Séparateur virgule FR
    // -------------------------------------------------------------------------
    test('virgule FR acceptée — "45,5" → 45.5', () {
      expect(SurfaceValidator.parse('45,5'), equals(45.5));
    });

    test('virgule FR — "1,0" → 1.0', () {
      expect(SurfaceValidator.parse('1,0'), equals(1.0));
    });

    // -------------------------------------------------------------------------
    // Séparateur point
    // -------------------------------------------------------------------------
    test('point décimal accepté — "45.5" → 45.5', () {
      expect(SurfaceValidator.parse('45.5'), equals(45.5));
    });

    // -------------------------------------------------------------------------
    // Entier
    // -------------------------------------------------------------------------
    test('entier accepté — "100" → 100.0', () {
      expect(SurfaceValidator.parse('100'), equals(100.0));
    });

    // -------------------------------------------------------------------------
    // Valeur minimale valide
    // -------------------------------------------------------------------------
    test('valeur minimale — "0,01" → 0.01', () {
      expect(SurfaceValidator.parse('0,01'), closeTo(0.01, 0.001));
    });

    // -------------------------------------------------------------------------
    // Valeur maximale valide
    // -------------------------------------------------------------------------
    test('valeur maximale — "9999,99" → 9999.99', () {
      expect(SurfaceValidator.parse('9999,99'), closeTo(9999.99, 0.001));
    });

    // -------------------------------------------------------------------------
    // Zéro — invalide (surface doit être > 0)
    // -------------------------------------------------------------------------
    test('zéro lève SurfaceValidationException "positive"', () {
      expect(
        () => SurfaceValidator.parse('0'),
        throwsA(
          isA<SurfaceValidationException>().having(
            (e) => e.message,
            'message',
            contains('positive'),
          ),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Négatif
    // -------------------------------------------------------------------------
    test('valeur négative lève SurfaceValidationException "positive"', () {
      expect(
        () => SurfaceValidator.parse('-5'),
        throwsA(
          isA<SurfaceValidationException>().having(
            (e) => e.message,
            'message',
            contains('positive'),
          ),
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Trop grand
    // -------------------------------------------------------------------------
    test('valeur > 9999,99 lève SurfaceValidationException "maximale"', () {
      expect(
        () => SurfaceValidator.parse('10000'),
        throwsA(
          isA<SurfaceValidationException>().having(
            (e) => e.message,
            'message',
            contains('maximale'),
          ),
        ),
      );
    });

    test('"9999,999" est > 9999.99 → lève exception maximale', () {
      expect(
        () => SurfaceValidator.parse('9999,999'),
        throwsA(isA<SurfaceValidationException>()),
      );
    });

    // -------------------------------------------------------------------------
    // Texte non numérique
    // -------------------------------------------------------------------------
    test('texte non numérique lève SurfaceValidationException "invalide"', () {
      expect(
        () => SurfaceValidator.parse('abc'),
        throwsA(
          isA<SurfaceValidationException>().having(
            (e) => e.message,
            'message',
            contains('invalide'),
          ),
        ),
      );
    });

    test('texte mixte "45m²" lève exception invalide', () {
      expect(
        () => SurfaceValidator.parse('45m²'),
        throwsA(isA<SurfaceValidationException>()),
      );
    });
  });

  group('SurfaceValidator.validate', () {
    test('vide retourne null (pas d\'erreur)', () {
      expect(SurfaceValidator.validate(''), isNull);
    });

    test('null retourne null (pas d\'erreur)', () {
      expect(SurfaceValidator.validate(null), isNull);
    });

    test('valeur valide retourne null', () {
      expect(SurfaceValidator.validate('50'), isNull);
    });

    test('valeur négative retourne message d\'erreur', () {
      expect(SurfaceValidator.validate('-1'), isNotNull);
    });

    test('trop grand retourne message d\'erreur', () {
      expect(SurfaceValidator.validate('99999'), isNotNull);
    });

    test('virgule FR retourne null (valide)', () {
      expect(SurfaceValidator.validate('12,5'), isNull);
    });
  });
}
