/// Tests unitaires pour [PropertyColorKey] / [PropertyColorPalette]
/// (FEAT-057 — couleur d'identité des biens).
library;

import 'dart:math' as math;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/theme/property_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Luminance relative WCAG (formule officielle, indépendante de
/// l'implémentation testée — sert de garde-fou anti-régression sur le
/// contraste du fond de carte teinté).
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Ratio de contraste WCAG entre deux couleurs.
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a) + 0.05;
  final lb = _relativeLuminance(b) + 0.05;
  return la > lb ? la / lb : lb / la;
}

void main() {
  group('PropertyColorKey.parse', () {
    test('null → null', () {
      expect(PropertyColorKey.parse(null), isNull);
    });

    test('chaîne vide → null', () {
      expect(PropertyColorKey.parse(''), isNull);
    });

    test('valeur inconnue → null (tolérance au drift)', () {
      expect(PropertyColorKey.parse('turquoise-fluo'), isNull);
    });

    test('valeur connue → enum correspondant', () {
      expect(PropertyColorKey.parse('cobalt'), PropertyColorKey.cobalt);
      expect(PropertyColorKey.parse('rosePoudre'), PropertyColorKey.rosePoudre);
    });
  });

  group('PropertyColorKey.resolve', () {
    test('stored valide → utilisée telle quelle (prime sur le repli)', () {
      final resolved = PropertyColorKey.resolve(
        entityId: 'any-id',
        stored: 'sauge',
      );
      expect(resolved, PropertyColorKey.sauge);
    });

    test('stored null → repli déterministe (jamais null)', () {
      final resolved = PropertyColorKey.resolve(entityId: 'prop-123');
      expect(PropertyColorKey.values, contains(resolved));
    });

    test('stored inconnue (drift) → repli déterministe, comme si absente', () {
      final withUnknown = PropertyColorKey.resolve(
        entityId: 'prop-123',
        stored: 'couleur-retirée-de-la-palette',
      );
      final withNull = PropertyColorKey.resolve(entityId: 'prop-123');
      expect(withUnknown, withNull);
    });

    test('même id → toujours la même couleur (stabilité inter-appels)', () {
      final first = PropertyColorKey.resolve(entityId: 'prop-abc');
      for (var i = 0; i < 20; i++) {
        expect(PropertyColorKey.resolve(entityId: 'prop-abc'), first);
      }
    });

    test('ids différents → répartition sur plusieurs teintes (pas toujours la '
        'même case)', () {
      final resolvedKeys = {
        for (var i = 0; i < 50; i++)
          PropertyColorKey.resolve(entityId: 'property-uuid-$i'),
      };
      // Avec 50 ids différents sur 8 teintes, on doit voir plus d'une
      // teinte utilisée — un hash qui retomberait toujours sur la même
      // valeur serait un bug de résolution.
      expect(resolvedKeys.length, greaterThan(1));
    });

    test('id vide → ne plante pas, retombe sur une teinte valide', () {
      final resolved = PropertyColorKey.resolve(entityId: '');
      expect(PropertyColorKey.values, contains(resolved));
    });
  });

  group('PropertyColorPalette', () {
    test('light couvre les 8 teintes', () {
      for (final key in PropertyColorKey.values) {
        expect(PropertyColorPalette.light.swatches.containsKey(key), isTrue);
      }
    });

    test('dark couvre les 8 teintes', () {
      for (final key in PropertyColorKey.values) {
        expect(PropertyColorPalette.dark.swatches.containsKey(key), isTrue);
      }
    });

    test('light et dark diffèrent pour chaque teinte (pas un doublon '
        'copié-collé)', () {
      for (final key in PropertyColorKey.values) {
        expect(
          PropertyColorPalette.light.of(key),
          isNot(PropertyColorPalette.dark.of(key)),
          reason: '$key devrait avoir une teinte distincte en dark mode',
        );
      }
    });

    test('of() sur une teinte manquante (drift enum) replie sur la première '
        'teinte connue plutôt que planter', () {
      const partial = PropertyColorPalette(
        swatches: {PropertyColorKey.rouille: Color(0xFF123456)},
      );
      expect(partial.of(PropertyColorKey.cobalt), const Color(0xFF123456));
    });

    test('lerp(t=0) → couleurs de départ', () {
      final lerped = PropertyColorPalette.light.lerp(
        PropertyColorPalette.dark,
        0,
      );
      for (final key in PropertyColorKey.values) {
        expect(lerped.of(key), PropertyColorPalette.light.of(key));
      }
    });

    test('lerp(t=1) → couleurs d\'arrivée', () {
      final lerped = PropertyColorPalette.light.lerp(
        PropertyColorPalette.dark,
        1,
      );
      for (final key in PropertyColorKey.values) {
        expect(lerped.of(key), PropertyColorPalette.dark.of(key));
      }
    });

    test('lerp(null) → retourne this (no-op, même pattern que AppColors)', () {
      final result = PropertyColorPalette.light.lerp(null, 0.5);
      expect(result, same(PropertyColorPalette.light));
    });

    test('copyWith sans argument → mêmes swatches', () {
      final copy = PropertyColorPalette.light.copyWith();
      expect(copy.swatches, PropertyColorPalette.light.swatches);
    });
  });

  group('PropertyColorKeyThemeX.resolveColor', () {
    testWidgets('résout via le ThemeExtension enregistré', (tester) async {
      late Color resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [PropertyColorPalette.light]),
          home: Builder(
            builder: (context) {
              resolved = PropertyColorKey.cobalt.resolveColor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, PropertyColorPalette.light.of(PropertyColorKey.cobalt));
    });

    testWidgets('sans extension enregistrée → replie sur la palette claire '
        '(défense en profondeur pour les tests widget)', (tester) async {
      late Color resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(
            builder: (context) {
              resolved = PropertyColorKey.moutarde.resolveColor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        resolved,
        PropertyColorPalette.light.of(PropertyColorKey.moutarde),
      );
    });
  });

  group('PropertyColorKeyThemeX.resolveCardBackground', () {
    const base = Color(0xFFF7F4ED); // paper — surfaceContainerLow clair

    testWidgets('mélange l\'accent avec la base fournie (alpha blend '
        'documenté, jamais la couleur brute)', (tester) async {
      late Color result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [PropertyColorPalette.light]),
          home: Builder(
            builder: (context) {
              result = PropertyColorKey.cobalt.resolveCardBackground(
                context,
                base,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final expected = Color.alphaBlend(
        PropertyColorPalette.light
            .of(PropertyColorKey.cobalt)
            .withValues(alpha: 0.08),
        base,
      );
      expect(result, expected);
      // Ni la base pure, ni l'accent pur : un vrai mélange.
      expect(result, isNot(base));
      expect(
        result,
        isNot(PropertyColorPalette.light.of(PropertyColorKey.cobalt)),
      );
    });

    testWidgets('résultat distinct pour deux teintes différentes (le fond '
        'reste discriminant entre biens)', (tester) async {
      late Color cobaltBg, rouilleBg;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [PropertyColorPalette.light]),
          home: Builder(
            builder: (context) {
              cobaltBg = PropertyColorKey.cobalt.resolveCardBackground(
                context,
                base,
              );
              rouilleBg = PropertyColorKey.rouille.resolveCardBackground(
                context,
                base,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(cobaltBg, isNot(rouilleBg));
    });

    // --- Garde-fou contraste WCAG AA -----------------------------------
    //
    // Le plan FEAT-057 exige un ratio ≥ 4,5:1 (AA, texte normal) pour les 8
    // teintes × 2 thèmes × (fond idle `surfaceContainerLow`, fond hover
    // `surfaceContainerHigh`) × (texte `onSurface`, `onSurfaceVariant`).
    // Ce test recalcule le ratio via la formule WCAG officielle (indépendante
    // de l'implémentation) : toute variation de `_cardBackgroundOpacity` ou
    // de la palette qui ferait passer un seul cas sous 4,5:1 doit le faire
    // échouer.
    testWidgets(
      'fond de carte teinté : contraste AA (≥4,5:1) tenu pour les 8 teintes, '
      'les 2 thèmes, idle/hover, onSurface/onSurfaceVariant',
      (tester) async {
        for (final themeEntry in {
          'light': AppTheme.light,
          'dark': AppTheme.dark,
        }.entries) {
          final theme = themeEntry.value;
          final bases = [
            theme.colorScheme.surfaceContainerLow,
            theme.colorScheme.surfaceContainerHigh,
          ];
          final texts = [
            theme.colorScheme.onSurface,
            theme.colorScheme.onSurfaceVariant,
          ];

          final results =
              <(Color base, Color text, PropertyColorKey key, Color bg)>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Builder(
                builder: (context) {
                  for (final base in bases) {
                    for (final text in texts) {
                      for (final key in PropertyColorKey.values) {
                        results.add((
                          base,
                          text,
                          key,
                          key.resolveCardBackground(context, base),
                        ));
                      }
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

          expect(results, hasLength(bases.length * texts.length * 8));
          for (final (base, text, key, bg) in results) {
            final ratio = _contrastRatio(text, bg);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  'thème ${themeEntry.key}, teinte ${key.name} : ratio '
                  '$ratio < 4,5:1 (AA) — base=$base, texte=$text, fond=$bg',
            );
          }
        }
      },
    );
  });
}
