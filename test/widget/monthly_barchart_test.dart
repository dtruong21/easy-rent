/// Tests widget de [MonthlyBarchart] — toggle de format de graphique.
///
/// Couvre :
/// - Défaut : barres (BarChart) + toggle visible
/// - Courbes / Aires → LineChart, choix persisté
/// - Données à zéro → empty state, toggle masqué
library;

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/dashboard/domain/chart_format.dart';
import 'package:easyrent/features/dashboard/domain/monthly_amount.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/monthly_barchart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<MonthlyAmount> _makeMonths({bool empty = false}) => [
  for (int i = 1; i <= 6; i++)
    MonthlyAmount(
      year: 2026,
      month: i,
      encaissedCents: empty ? 0 : 65000 * i,
      dueCents: empty ? 0 : 70000 * i,
    ),
];

Widget _buildChart(List<MonthlyAmount> months) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      extensions: const [AppColors.light, AppRadii()],
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: MonthlyBarchart(months: months)),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MonthlyBarchart — formats', () {
    testWidgets('défaut : barres + toggle visible', (tester) async {
      await tester.pumpWidget(_buildChart(_makeMonths()));
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(find.byKey(const Key('segments_chart_format')), findsOneWidget);
    });

    testWidgets('tap « Courbes » → LineChart + persistance', (tester) async {
      await tester.pumpWidget(_buildChart(_makeMonths()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.show_chart));
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chart_format_monthly'), 'line');
    });

    testWidgets('tap « Aires » → LineChart avec aires remplies', (
      tester,
    ) async {
      await tester.pumpWidget(_buildChart(_makeMonths()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.area_chart_outlined));
      await tester.pumpAndSettle();

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.every((s) => s.belowBarData.show), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chart_format_monthly'), 'area');
    });

    testWidgets('préférence persistée « line » → LineChart au montage', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'chart_format_monthly': 'line'});

      await tester.pumpWidget(_buildChart(_makeMonths()));
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('données à zéro → empty state, toggle masqué', (tester) async {
      await tester.pumpWidget(_buildChart(_makeMonths(empty: true)));
      await tester.pumpAndSettle();

      expect(find.text("Pas encore d'historique"), findsOneWidget);
      expect(find.byKey(const Key('segments_chart_format')), findsNothing);
    });
  });

  group('ChartFormat', () {
    test('fromName parse les valeurs connues, null sinon', () {
      expect(ChartFormat.fromName('bars'), ChartFormat.bars);
      expect(ChartFormat.fromName('line'), ChartFormat.line);
      expect(ChartFormat.fromName('area'), ChartFormat.area);
      expect(ChartFormat.fromName('donut'), isNull);
      expect(ChartFormat.fromName(null), isNull);
    });
  });
}
