/// Garde-fou des jetons de design ajoutés au brand polish post FEAT-020.
///
/// Vérifie que les hex sont préservés (un changement intempestif casse la
/// charte) et que les alias sémantiques métier pointent bien vers les bons
/// jetons techniques. Voir docs/state/DESIGN_TOKENS.md pour la table d'usage.
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme — jetons d\'extension brand polish', () {
    test('sealGreen = #2E5339', () {
      expect(AppTheme.sealGreen, const Color(0xFF2E5339));
    });

    test('ochre = #7E5612', () {
      expect(AppTheme.ochre, const Color(0xFF7E5612));
    });

    test('indigoInk = #2A3656', () {
      expect(AppTheme.indigoInk, const Color(0xFF2A3656));
    });

    test('kraft = #E4D9BD', () {
      expect(AppTheme.kraft, const Color(0xFFE4D9BD));
    });

    test('stone = #A8A39A', () {
      expect(AppTheme.stone, const Color(0xFFA8A39A));
    });

    test('oliveDeep = #34401F', () {
      expect(AppTheme.oliveDeep, const Color(0xFF34401F));
    });

    test('ruleStrong = #C9C1AB', () {
      expect(AppTheme.ruleStrong, const Color(0xFFC9C1AB));
    });

    test('amountNegative = #6E3A1F', () {
      expect(AppTheme.amountNegative, const Color(0xFF6E3A1F));
    });
  });

  group('AppTheme — alias sémantiques métier', () {
    test('acquitte → sealGreen', () {
      expect(AppTheme.acquitte, AppTheme.sealGreen);
    });

    test('echu → ochre', () {
      expect(AppTheme.echu, AppTheme.ochre);
    });

    test('consigne → indigoInk', () {
      expect(AppTheme.consigne, AppTheme.indigoInk);
    });

    test('archive → kraft', () {
      expect(AppTheme.archive, AppTheme.kraft);
    });
  });

  group('AppTheme — palette de base inchangée par le polish', () {
    // Garde-fou : le polish ne doit pas dériver la palette FEAT-020.
    test('paper, ink, olive, oxblood restent les hex FEAT-020', () {
      expect(AppTheme.paper, const Color(0xFFF7F4ED));
      expect(AppTheme.ink, const Color(0xFF1B1A17));
      expect(AppTheme.olive, const Color(0xFF3F4A2A));
      expect(AppTheme.oxblood, const Color(0xFF9A3B2F));
    });
  });
}
