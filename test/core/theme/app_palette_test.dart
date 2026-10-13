import 'package:easyrent/core/theme/app_palette.g.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Verrou de la chaîne complète pour les 19 couleurs :
  //   valeur canonique (config/theme_tokens.json, recopiée ici en dur)
  //     -> miroir généré (AppPalette.<nom>)
  //     -> délégation (AppTheme.<nom>)
  //
  // Égalité Color directe (pas de toARGB32(), qui dépend d'une API récente
  // non vérifiée sur le pin CI Flutter 3.41.2) — même approche que le test
  // verrou déjà existant, test/core/theme/app_theme_design_tokens_test.dart,
  // qui compare `AppTheme.sealGreen` à `const Color(0xFF2E5339)`.
  //
  // Ce test couvre les 19 couleurs pour AppTheme, y compris les 7 qui
  // n'étaient vérifiées via AppTheme.<nom> par aucun test avant celui-ci :
  // paperDeep, cream, inkSurface, inkMuted, rule, oliveMid, oliveSoft. Une
  // régression comme `paperDeep = AppPalette.paper` (copier-coller fautif
  // dans app_theme.dart) ferait échouer ce test même si AppPalette lui-même
  // reste correct.
  const cases = <String, (Color canonical, Color palette, Color theme)>{
    'paper': (Color(0xFFF7F4ED), AppPalette.paper, AppTheme.paper),
    'paperDeep': (Color(0xFFEFE9DA), AppPalette.paperDeep, AppTheme.paperDeep),
    'cream': (Color(0xFFFCFAF5), AppPalette.cream, AppTheme.cream),
    'ink': (Color(0xFF1B1A17), AppPalette.ink, AppTheme.ink),
    'inkSurface': (
      Color(0xFF2A2823),
      AppPalette.inkSurface,
      AppTheme.inkSurface,
    ),
    'inkMuted': (Color(0xFF6B665D), AppPalette.inkMuted, AppTheme.inkMuted),
    'rule': (Color(0xFFE8E2D3), AppPalette.rule, AppTheme.rule),
    'olive': (Color(0xFF3F4A2A), AppPalette.olive, AppTheme.olive),
    'oliveMid': (Color(0xFF5E6A45), AppPalette.oliveMid, AppTheme.oliveMid),
    'oliveSoft': (Color(0xFFB5B89D), AppPalette.oliveSoft, AppTheme.oliveSoft),
    'oxblood': (Color(0xFF9A3B2F), AppPalette.oxblood, AppTheme.oxblood),
    'sealGreen': (Color(0xFF2E5339), AppPalette.sealGreen, AppTheme.sealGreen),
    'ochre': (Color(0xFF7E5612), AppPalette.ochre, AppTheme.ochre),
    'indigoInk': (Color(0xFF2A3656), AppPalette.indigoInk, AppTheme.indigoInk),
    'kraft': (Color(0xFFE4D9BD), AppPalette.kraft, AppTheme.kraft),
    'stone': (Color(0xFFA8A39A), AppPalette.stone, AppTheme.stone),
    'oliveDeep': (Color(0xFF34401F), AppPalette.oliveDeep, AppTheme.oliveDeep),
    'ruleStrong': (
      Color(0xFFC9C1AB),
      AppPalette.ruleStrong,
      AppTheme.ruleStrong,
    ),
    'amountNegative': (
      Color(0xFF6E3A1F),
      AppPalette.amountNegative,
      AppTheme.amountNegative,
    ),
  };

  test('les 19 couleurs : valeur canonique = AppPalette = AppTheme', () {
    expect(
      cases.length,
      19,
      reason: 'une couleur a été ajoutée ou retirée de la palette',
    );
    for (final entry in cases.entries) {
      final (canonical, palette, theme) = entry.value;
      expect(
        palette,
        canonical,
        reason: 'AppPalette.${entry.key} a changé de valeur',
      );
      expect(
        theme,
        canonical,
        reason:
            'AppTheme.${entry.key} ne délègue plus vers la valeur canonique '
            '(délégation cassée ou mauvais jeton copié)',
      );
    }
  });
}
