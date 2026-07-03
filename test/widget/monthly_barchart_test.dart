/// Tests widget de [MonthlyBarchart] — toggle de format + période de graphique.
///
/// Couvre :
/// - Défaut : barres (BarChart) + toggles visibles
/// - Courbes / Aires → LineChart, choix persisté
/// - Données à zéro → empty state, toggles masqués
/// - Loading / error de [monthlyAmountsProvider]
/// - Bascule de période (6/12/24 mois) → N barres/points, persistance
library;

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/dashboard/application/dashboard_provider.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/chart_format.dart';
import 'package:easyrent/features/dashboard/domain/chart_period.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/monthly_amount.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/monthly_barchart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake repository — sert monthlyAmountsProvider selon la période demandée.
// ---------------------------------------------------------------------------

List<MonthlyAmount> _makeMonths(int count, {bool empty = false}) => [
  for (int i = 1; i <= count; i++)
    MonthlyAmount(
      year: 2026,
      month: ((i - 1) % 12) + 1,
      encaissedCents: empty ? 0 : 65000 * i,
      dueCents: empty ? 0 : 70000 * i,
    ),
];

class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository({this.empty = false, this.throwError = false});

  final bool empty;
  final bool throwError;

  @override
  Future<List<MonthlyAmount>> fetchLastMonthsAmounts(int months) async {
    if (throwError) {
      throw StateError('fetch failed');
    }
    return _makeMonths(months, empty: empty);
  }

  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async =>
      const LoyersMoisKpi(encaissedCents: 0, dueCents: 0);
  @override
  Future<RetardsKpi> fetchRetards() async => const RetardsKpi(count: 0);
  @override
  Future<RenouvellementsKpi> fetchRenouvellements() async =>
      const RenouvellementsKpi(count: 0);
  @override
  Future<DocsPendingKpi> fetchDocsPending() async =>
      const DocsPendingKpi(count: 0);
  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async => [];
  @override
  Future<bool> isLandlordOnboarding() async => false;
}

// ---------------------------------------------------------------------------
// Harnais de rendu
// ---------------------------------------------------------------------------

Widget _buildChart({bool empty = false, bool throwError = false}) =>
    ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(
          _FakeDashboardRepository(empty: empty, throwError: throwError),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          extensions: const [AppColors.light, AppRadii()],
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: MonthlyBarchart()),
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MonthlyBarchart — formats', () {
    testWidgets('défaut : barres + toggles visibles', (tester) async {
      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(find.byKey(const Key('segments_chart_format')), findsOneWidget);
      expect(find.byKey(const Key('segments_chart_period')), findsOneWidget);
    });

    testWidgets('tap « Courbes » → LineChart + persistance', (tester) async {
      await tester.pumpWidget(_buildChart());
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
      await tester.pumpWidget(_buildChart());
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

      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('données à zéro → empty state, toggles masqués', (
      tester,
    ) async {
      await tester.pumpWidget(_buildChart(empty: true));
      await tester.pumpAndSettle();

      expect(find.text("Pas encore d'historique"), findsOneWidget);
      expect(find.byKey(const Key('segments_chart_format')), findsNothing);
      expect(find.byKey(const Key('segments_chart_period')), findsNothing);
    });
  });

  group('MonthlyBarchart — chargement / erreur', () {
    testWidgets('affiche un indicateur de progression pendant le chargement', (
      tester,
    ) async {
      await tester.pumpWidget(_buildChart());
      // Juste après pumpWidget (avant tout autre pump) : le FutureProvider
      // est encore en loading — même pattern que dashboard_page_test.dart.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('affiche un message sobre en cas d\'erreur', (tester) async {
      await tester.pumpWidget(_buildChart(throwError: true));
      await tester.pumpAndSettle();

      expect(
        find.text('Impossible de charger les loyers pour cette période.'),
        findsOneWidget,
      );
      // Le titre reste affiché même en erreur.
      expect(find.text('Loyers'), findsOneWidget);
    });
  });

  group('MonthlyBarchart — période sélectionnable', () {
    testWidgets('défaut 6 mois → 6 groupes de barres', (tester) async {
      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 6);
    });

    testWidgets('tap « 12 mois » → 12 groupes de barres + persistance', (
      tester,
    ) async {
      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      await tester.tap(find.text('12 mois'));
      await tester.pumpAndSettle();

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 12);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chart_period_monthly'), 'm12');
    });

    testWidgets('tap « 24 mois » → 24 groupes de barres + persistance', (
      tester,
    ) async {
      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      await tester.tap(find.text('24 mois'));
      await tester.pumpAndSettle();

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 24);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chart_period_monthly'), 'm24');
    });

    testWidgets('préférence persistée « m12 » → 12 mois au montage', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'chart_period_monthly': 'm12'});

      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 12);
    });

    testWidgets(
      'bascule de période ne casse pas le format sélectionné (courbes)',
      (tester) async {
        await tester.pumpWidget(_buildChart());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.show_chart));
        await tester.pumpAndSettle();

        await tester.tap(find.text('12 mois'));
        await tester.pumpAndSettle();

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        expect(chart.data.lineBarsData.first.spots.length, 12);
      },
    );

    testWidgets('empty state à toutes périodes (24 mois vide)', (tester) async {
      SharedPreferences.setMockInitialValues({'chart_period_monthly': 'm24'});

      await tester.pumpWidget(_buildChart(empty: true));
      await tester.pumpAndSettle();

      expect(find.text("Pas encore d'historique"), findsOneWidget);
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

  group('ChartPeriod', () {
    test('months retourne le bon nombre de mois', () {
      expect(ChartPeriod.m6.months, 6);
      expect(ChartPeriod.m12.months, 12);
      expect(ChartPeriod.m24.months, 24);
    });

    test('fromName parse les valeurs connues, null sinon', () {
      expect(ChartPeriod.fromName('m6'), ChartPeriod.m6);
      expect(ChartPeriod.fromName('m12'), ChartPeriod.m12);
      expect(ChartPeriod.fromName('m24'), ChartPeriod.m24);
      expect(ChartPeriod.fromName('m36'), isNull);
      expect(ChartPeriod.fromName(null), isNull);
    });
  });
}
