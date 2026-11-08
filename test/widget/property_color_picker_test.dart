/// Tests widget pour [PropertyColorPicker] (FEAT-057 — couleur d'identité).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/theme/property_color.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_color_picker.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('PropertyColorPicker — rendu', () {
    testWidgets('affiche une pastille par teinte de la palette', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PropertyColorPicker(
            selected: PropertyColorKey.cobalt,
            onChanged: (_) {},
          ),
        ),
      );

      for (final key in PropertyColorKey.values) {
        expect(find.byKey(Key('color_swatch_${key.name}')), findsOneWidget);
      }
    });

    testWidgets(
      'la pastille sélectionnée porte Semantics(selected: true)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PropertyColorPicker(
              selected: PropertyColorKey.sauge,
              onChanged: (_) {},
            ),
          ),
        );

        expect(
          tester.getSemantics(find.byKey(const Key('color_swatch_sauge'))),
          matchesSemantics(
            label: 'Couleur Sauge',
            isButton: true,
            isSelected: true,
            isFocusable: true,
            hasSelectedState: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.byKey(const Key('color_swatch_cobalt'))),
          matchesSemantics(
            label: 'Couleur Cobalt',
            isButton: true,
            isSelected: false,
            isFocusable: true,
            hasSelectedState: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
      },
      semanticsEnabled: true,
    );
  });

  group('PropertyColorPicker — interaction', () {
    testWidgets('tap sur une pastille → onChanged appelé avec sa clé', (
      tester,
    ) async {
      PropertyColorKey? tapped;
      await tester.pumpWidget(
        _wrap(
          PropertyColorPicker(
            selected: PropertyColorKey.cobalt,
            onChanged: (key) => tapped = key,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('color_swatch_moutarde')));
      await tester.pumpAndSettle();

      expect(tapped, PropertyColorKey.moutarde);
    });

    testWidgets('enabled=false → tap sans effet', (tester) async {
      PropertyColorKey? tapped;
      await tester.pumpWidget(
        _wrap(
          PropertyColorPicker(
            selected: PropertyColorKey.cobalt,
            enabled: false,
            onChanged: (key) => tapped = key,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('color_swatch_moutarde')));
      await tester.pumpAndSettle();

      expect(tapped, isNull);
    });
  });
}
