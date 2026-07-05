/// Tests de [FrenchDate].
///
/// Couvre :
/// - format : padding dd/MM/yyyy + conversion UTC → heure locale
/// - formatIsoString : date seule, timestamp ISO complet (régression
///   « 30T22:00:00.000Z/06/2026 » sur la liste locataires), entrées
///   défensives (vide / format inattendu)
library;

import 'package:easyrent/core/utils/french_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrenchDate.format', () {
    test('dd/MM/yyyy avec padding', () {
      expect(FrenchDate.format(DateTime(2026, 7, 1)), '01/07/2026');
      expect(FrenchDate.format(DateTime(2026, 11, 25)), '25/11/2026');
    });

    test('timestamp UTC → jour LOCAL (pas le jour UTC)', () {
      // Minuit local converti en UTC peut tomber la veille (ex. Paris été :
      // 2026-07-01 00:00+02:00 == 2026-06-30T22:00Z). L'affichage doit
      // rendre le jour local choisi, pas le jour UTC.
      final localMidnight = DateTime(2026, 7, 1);
      expect(FrenchDate.format(localMidnight.toUtc()), '01/07/2026');
    });
  });

  group('FrenchDate.formatIsoString', () {
    test('date seule YYYY-MM-DD', () {
      expect(FrenchDate.formatIsoString('2026-07-01'), '01/07/2026');
    });

    test('timestamp ISO complet → dd/MM/yyyy en heure locale (régression '
        '« Depuis 30T22:00:00.000Z/06/2026 », liste + fiche locataires)', () {
      final iso = DateTime(2026, 7, 1).toUtc().toIso8601String();
      expect(FrenchDate.formatIsoString(iso), '01/07/2026');
    });

    test('vide → vide', () {
      expect(FrenchDate.formatIsoString(''), '');
    });

    test('format inattendu → inchangé (défensif)', () {
      expect(FrenchDate.formatIsoString('n/a'), 'n/a');
      expect(FrenchDate.formatIsoString('juillet 2026'), 'juillet 2026');
    });
  });

  group('FrenchDate.frenchMonthYear', () {
    test('libellé mois + année en français', () {
      expect(FrenchDate.frenchMonthYear(DateTime(2026, 3, 15)), 'mars 2026');
    });
  });
}
