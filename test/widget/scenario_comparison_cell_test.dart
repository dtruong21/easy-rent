/// Tests widget pour [ScenarioComparisonCell] (responsive rework, FEAT-055).
///
/// Vérifie que le delta favorable/défavorable/neutre utilise bien des tokens
/// du thème Baillan (jamais de couleur en dur type `Colors.green`), et que
/// ce rendu reste correct en light **et** dark mode.
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/features/simulator/domain/scenario_comparison_view_model.dart';
import 'package:easyrent/features/simulator/presentation/widgets/scenario_comparison_cell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {required ThemeData theme}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('ScenarioComparisonCell — couleurs du thème (light)', () {
    testWidgets('delta favorable → AppColors.success.solid', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ScenarioComparisonCell(
            value: ComparisonValue(rawNumber: 10, display: '10,00 %'),
            deltaPercent: 12.5,
            higherIsBetter: true,
          ),
          theme: AppTheme.light,
        ),
      );

      final deltaText = tester.widget<Text>(find.text('+12,5 %'));
      expect(
        deltaText.style?.color,
        AppTheme.light.extension<AppColors>()!.success.solid,
      );
    });

    testWidgets('delta défavorable → colorScheme.error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ScenarioComparisonCell(
            value: ComparisonValue(rawNumber: 10, display: '10,00 %'),
            deltaPercent: -12.5,
            higherIsBetter: true,
          ),
          theme: AppTheme.light,
        ),
      );

      final deltaText = tester.widget<Text>(find.text('−12,5 %'));
      expect(deltaText.style?.color, AppTheme.light.colorScheme.error);
    });

    testWidgets('delta sous le seuil de ±5% → onSurfaceVariant (neutre)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ScenarioComparisonCell(
            value: ComparisonValue(rawNumber: 10, display: '10,00 %'),
            deltaPercent: 3.0,
            higherIsBetter: true,
          ),
          theme: AppTheme.light,
        ),
      );

      final deltaText = tester.widget<Text>(find.text('+3,0 %'));
      expect(
        deltaText.style?.color,
        AppTheme.light.colorScheme.onSurfaceVariant,
      );
    });
  });

  group('ScenarioComparisonCell — couleurs du thème (dark)', () {
    testWidgets('delta favorable → AppColors.success.solid (dark)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ScenarioComparisonCell(
            value: ComparisonValue(rawNumber: 10, display: '10,00 %'),
            deltaPercent: 12.5,
            higherIsBetter: true,
          ),
          theme: AppTheme.dark,
        ),
      );

      final deltaText = tester.widget<Text>(find.text('+12,5 %'));
      expect(
        deltaText.style?.color,
        AppTheme.dark.extension<AppColors>()!.success.solid,
      );
      // Contraste garanti par la palette AppColors dark (déclinée pour le
      // ground ink) — distincte de la valeur light.
      expect(
        deltaText.style?.color,
        isNot(AppTheme.light.extension<AppColors>()!.success.solid),
      );
    });

    testWidgets('delta défavorable → colorScheme.error (dark)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ScenarioComparisonCell(
            value: ComparisonValue(rawNumber: 10, display: '10,00 %'),
            deltaPercent: -12.5,
            higherIsBetter: true,
          ),
          theme: AppTheme.dark,
        ),
      );

      final deltaText = tester.widget<Text>(find.text('−12,5 %'));
      expect(deltaText.style?.color, AppTheme.dark.colorScheme.error);
    });
  });

  group('ScenarioComparisonCell — sens économique inversé', () {
    testWidgets('higherIsBetter=false + delta négatif → favorable (success)', (
      tester,
    ) async {
      // Coût de crédit, apport, effort d'épargne : plus bas = meilleur.
      await tester.pumpWidget(
        _wrap(
          const ScenarioComparisonCell(
            value: ComparisonValue(rawNumber: 10, display: '10,00 %'),
            deltaPercent: -8.0,
            higherIsBetter: false,
          ),
          theme: AppTheme.light,
        ),
      );

      final deltaText = tester.widget<Text>(find.text('−8,0 %'));
      expect(
        deltaText.style?.color,
        AppTheme.light.extension<AppColors>()!.success.solid,
      );
    });
  });
}
