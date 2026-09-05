import 'package:easyrent/core/theme/app_palette.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Valeurs relevées dans app_theme.dart AVANT la migration vers la source
  // canonique. Si l'une d'elles change, le rendu de l'app change — ce test
  // existe pour rendre ce changement impossible par accident.
  const expected = <String, int>{
    'paper': 0xFFF7F4ED,
    'paperDeep': 0xFFEFE9DA,
    'cream': 0xFFFCFAF5,
    'ink': 0xFF1B1A17,
    'inkSurface': 0xFF2A2823,
    'inkMuted': 0xFF6B665D,
    'rule': 0xFFE8E2D3,
    'olive': 0xFF3F4A2A,
    'oliveMid': 0xFF5E6A45,
    'oliveSoft': 0xFFB5B89D,
    'oxblood': 0xFF9A3B2F,
    'sealGreen': 0xFF2E5339,
    'ochre': 0xFF7E5612,
    'indigoInk': 0xFF2A3656,
    'kraft': 0xFFE4D9BD,
    'stone': 0xFFA8A39A,
    'oliveDeep': 0xFF34401F,
    'ruleStrong': 0xFFC9C1AB,
    'amountNegative': 0xFF6E3A1F,
  };

  test('les 19 couleurs générées valent exactement celles d\'avant', () {
    final actual = <String, Color>{
      'paper': AppPalette.paper,
      'paperDeep': AppPalette.paperDeep,
      'cream': AppPalette.cream,
      'ink': AppPalette.ink,
      'inkSurface': AppPalette.inkSurface,
      'inkMuted': AppPalette.inkMuted,
      'rule': AppPalette.rule,
      'olive': AppPalette.olive,
      'oliveMid': AppPalette.oliveMid,
      'oliveSoft': AppPalette.oliveSoft,
      'oxblood': AppPalette.oxblood,
      'sealGreen': AppPalette.sealGreen,
      'ochre': AppPalette.ochre,
      'indigoInk': AppPalette.indigoInk,
      'kraft': AppPalette.kraft,
      'stone': AppPalette.stone,
      'oliveDeep': AppPalette.oliveDeep,
      'ruleStrong': AppPalette.ruleStrong,
      'amountNegative': AppPalette.amountNegative,
    };

    expect(
      actual.length,
      expected.length,
      reason: 'une couleur a été ajoutée ou retirée de la palette',
    );
    for (final entry in expected.entries) {
      expect(
        actual[entry.key]!.toARGB32(),
        entry.value,
        reason: 'la couleur ${entry.key} a changé de valeur',
      );
    }
  });
}
