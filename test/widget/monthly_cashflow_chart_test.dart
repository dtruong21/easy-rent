/// Tests widget de [MonthlyCashflowChart] — toggle de format + période,
/// coloration sign(cash flow) → success/danger, mois sans donnée.
///
/// Couvre :
/// - Défaut : barres (BarChart) + toggles visibles
/// - Courbes / Aires → LineChart, choix persisté
/// - Aucune donnée sur la période → empty state, toggles masqués
/// - Loading / error de [monthlyCashflowProvider]
/// - Bascule de période (6/12/24 mois) → N barres/points, persistance
/// - Cohérence signe ↔ couleur : positif=success, négatif=danger, sans
///   donnée=neutre + hauteur nulle (négatif visible sous l'axe des abscisses)
library;

import 'package:easyrent/core/finance/expense_recurrence.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/dashboard/application/dashboard_provider.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/chart_format.dart';
import 'package:easyrent/features/dashboard/domain/chart_period.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/monthly_cashflow_chart.dart';
import 'package:easyrent/features/expenses/data/expenses_repository.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fakes — DashboardRepository (loyers encaissés) + ExpensesRepository
// ---------------------------------------------------------------------------

List<MonthlyCollectedRent> _makeRent(int count, {bool empty = false}) => [
  for (int i = 1; i <= count; i++)
    MonthlyCollectedRent(
      year: 2026,
      month: ((i - 1) % 12) + 1,
      collectedCents: empty ? 0 : 65000 * i,
      hasPayments: !empty,
    ),
];

/// Fake qui respecte le paramètre `months` (comme le vrai repo) — utilisé
/// pour les tests génériques de format/période/chargement/erreur.
class _PeriodAwareDashboardRepository implements DashboardRepository {
  _PeriodAwareDashboardRepository({
    this.empty = false,
    this.throwError = false,
  });

  final bool empty;
  final bool throwError;

  @override
  Future<List<MonthlyCollectedRent>> fetchLastMonthsCollectedRent(
    int months,
  ) async {
    if (throwError) {
      throw StateError('fetch failed');
    }
    return _makeRent(months, empty: empty);
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

/// Fake qui ignore `months` et retourne une liste fixe — utilisé pour le
/// test dédié à la cohérence signe ↔ couleur (données précises, indifférent
/// à la période affichée).
class _FixedDashboardRepository implements DashboardRepository {
  _FixedDashboardRepository(this._rent);
  final List<MonthlyCollectedRent> _rent;

  @override
  Future<List<MonthlyCollectedRent>> fetchLastMonthsCollectedRent(
    int months,
  ) async => _rent;

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

class _FakeExpensesRepository implements ExpensesRepository {
  const _FakeExpensesRepository([this.expenses = const []]);
  final List<Expense> expenses;

  @override
  Future<List<Expense>> listAllForLandlord() async => expenses;

  @override
  Future<List<Expense>> listForProperty(String propertyId) async =>
      throw UnimplementedError();
  @override
  Stream<List<Expense>> watchForProperty(String propertyId) =>
      throw UnimplementedError();
  @override
  Future<Expense> getById(String id) async => throw UnimplementedError();
  @override
  Future<Expense> create({
    required String propertyId,
    String? leaseId,
    required int amountCents,
    required DateTime expenseDate,
    required ExpenseNature nature,
    ExpenseCategory? category,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? periodYear,
    ExpenseRecurrence recurrence = ExpenseRecurrence.none,
    DateTime? recurrenceEndDate,
    String? documentId,
    String? notes,
  }) async => throw UnimplementedError();
  @override
  Future<Expense> update(Expense expense) async => throw UnimplementedError();
  @override
  Future<void> archive(String id) async => throw UnimplementedError();
}

Expense _expense({
  required String id,
  required int amountCents,
  required DateTime expenseDate,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: 'p1',
  amountCents: amountCents,
  expenseDate: expenseDate,
  nature: ExpenseNature.works,
  category: ExpenseCategory.nonRecoverable,
  periodYear: expenseDate.year,
  createdAt: expenseDate,
  updatedAt: expenseDate,
);

class _FakePropertyRepository implements PropertyRepository {
  const _FakePropertyRepository([this._properties = const []]);
  final List<Property> _properties;

  @override
  Future<List<Property>> list() async => _properties;

  @override
  Future<List<PropertyListItem>> listWithLeases() async =>
      throw UnimplementedError();
  @override
  Future<Property> getById(String id) async => throw UnimplementedError();
  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  }) async => throw UnimplementedError();
  @override
  Future<Property> update(Property property) async =>
      throw UnimplementedError();
  @override
  Future<int> countActiveLeases(String propertyId) async =>
      throw UnimplementedError();
  @override
  Future<void> archive(String id) async => throw UnimplementedError();
}

Property _property({
  DateTime? loanStartDate,
  int? loanMonthlyPaymentOverrideCents,
}) => Property(
  id: 'p1',
  landlordId: 'landlord-1',
  name: 'Bien Test',
  address: '1 rue Test',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  loanStartDate: loanStartDate,
  loanMonthlyPaymentOverrideCents: loanMonthlyPaymentOverrideCents,
);

// ---------------------------------------------------------------------------
// Harnais de rendu
// ---------------------------------------------------------------------------

Widget _wrap(
  DashboardRepository dashboardRepo,
  ExpensesRepository expensesRepo, {
  PropertyRepository? propertyRepo,
}) => ProviderScope(
  overrides: [
    dashboardRepositoryProvider.overrideWithValue(dashboardRepo),
    expensesRepositoryProvider.overrideWithValue(expensesRepo),
    if (propertyRepo != null)
      propertyRepositoryProvider.overrideWithValue(propertyRepo),
  ],
  child: MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      extensions: const [AppColors.light, AppRadii()],
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    locale: const Locale('fr'),
    home: const Scaffold(
      body: SingleChildScrollView(child: MonthlyCashflowChart()),
    ),
  ),
);

Widget _buildChart({bool empty = false, bool throwError = false}) => _wrap(
  _PeriodAwareDashboardRepository(empty: empty, throwError: throwError),
  const _FakeExpensesRepository(),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MonthlyCashflowChart — formats', () {
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

    testWidgets('tap « Aires » → LineChart avec aire remplie bornée à zéro', (
      tester,
    ) async {
      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.area_chart_outlined));
      await tester.pumpAndSettle();

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.belowBarData.show, isTrue);
      expect(chart.data.lineBarsData.single.belowBarData.applyCutOffY, isTrue);
      expect(chart.data.lineBarsData.single.belowBarData.cutOffY, 0);

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

    testWidgets('aucune donnée sur la période → empty state, toggles masqués', (
      tester,
    ) async {
      await tester.pumpWidget(_buildChart(empty: true));
      await tester.pumpAndSettle();

      expect(find.text("Pas encore d'historique"), findsOneWidget);
      expect(find.byKey(const Key('segments_chart_format')), findsNothing);
      expect(find.byKey(const Key('segments_chart_period')), findsNothing);
    });
  });

  group('MonthlyCashflowChart — chargement / erreur', () {
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
        find.text('Impossible de charger le cash-flow pour cette période.'),
        findsOneWidget,
      );
      // Le titre reste affiché même en erreur.
      expect(find.text('Cash-flow mensuel'), findsOneWidget);
    });
  });

  group('MonthlyCashflowChart — période sélectionnable', () {
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

  group('MonthlyCashflowChart — méthodologie et légende', () {
    testWidgets('affiche le sous-titre distinguant du cash flow lissé '
        '(Rentabilité portfolio)', (tester) async {
      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      expect(find.textContaining('non lissé'), findsOneWidget);
    });

    testWidgets('légende affiche Positif / Négatif', (tester) async {
      await tester.pumpWidget(_buildChart());
      await tester.pumpAndSettle();

      expect(find.text('Positif'), findsOneWidget);
      expect(find.text('Négatif'), findsOneWidget);
    });
  });

  group('MonthlyCashflowChart — cohérence signe ↔ couleur', () {
    testWidgets(
      'mois négatif=danger sous l\'axe, sans donnée=neutre hauteur nulle, '
      'mois positif=success',
      (tester) async {
        final now = DateTime.now();
        DateTime monthDate(int monthsAgo, [int day = 15]) =>
            DateTime(now.year, now.month - monthsAgo, day);

        final rent = [
          MonthlyCollectedRent(
            year: monthDate(2).year,
            month: monthDate(2).month,
            collectedCents: 50000,
            hasPayments: true,
          ),
          MonthlyCollectedRent(
            year: monthDate(1).year,
            month: monthDate(1).month,
            collectedCents: 0,
            hasPayments: false,
          ),
          MonthlyCollectedRent(
            year: monthDate(0).year,
            month: monthDate(0).month,
            collectedCents: 80000,
            hasPayments: true,
          ),
        ];
        // Grosse dépense sur le mois le plus ancien → net négatif
        // (50000 - 200000 = -150000 centimes).
        final expenses = [
          _expense(id: 'e1', amountCents: 200000, expenseDate: monthDate(2)),
        ];

        await tester.pumpWidget(
          _wrap(
            _FixedDashboardRepository(rent),
            _FakeExpensesRepository(expenses),
          ),
        );
        await tester.pumpAndSettle();

        final chart = tester.widget<BarChart>(find.byType(BarChart));
        final rods = [for (final g in chart.data.barGroups) g.barRods.single];
        expect(rods.length, 3);

        // Mois le plus ancien : négatif → sous l'axe (toY < 0), couleur danger.
        expect(rods[0].toY, lessThan(0));
        expect(rods[0].color, AppColors.light.danger.solid.withAlpha(200));

        // Mois intermédiaire : sans donnée → hauteur nulle, couleur neutre.
        expect(rods[1].toY, 0);
        expect(rods[1].color, AppColors.light.neutral.surface.withAlpha(200));

        // Mois le plus récent : positif → au-dessus de l'axe, couleur succès.
        expect(rods[2].toY, greaterThan(0));
        expect(rods[2].color, AppColors.light.success.solid.withAlpha(200));

        // L'échelle Y doit bien descendre sous zéro pour rendre le mois
        // négatif visible (pas de clipping à 0 en bas de graphique).
        expect(chart.data.minY, lessThan(0));
      },
    );
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

  group('MonthlyCashflowChart — mention « aucune dépense »', () {
    // Signalé en recette : le graphique affichait exactement les loyers et
    // semblait ignorer les dépenses. Le calcul était juste — le bailleur
    // n'avait saisi AUCUNE dépense. C'est l'absence d'explication qui a coûté
    // un aller-retour de diagnostic, pas le chiffre.
    // Fragment stable du libellé FR (le harnais force `Locale('fr')`).
    final noteFr = find.textContaining('Aucune dépense saisie');

    testWidgets('des loyers mais zéro dépense → la mention s\'affiche', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _PeriodAwareDashboardRepository(),
          const _FakeExpensesRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(noteFr, findsOneWidget);
    });

    testWidgets('au moins une dépense → pas de mention', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _PeriodAwareDashboardRepository(),
          _FakeExpensesRepository([
            _expense(
              id: 'e1',
              amountCents: 12000,
              expenseDate: DateTime(2026, 3, 15),
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(noteFr, findsNothing);
    });

    testWidgets('période entièrement vide → pas de mention (l\'état vide '
        'parle déjà)', (tester) async {
      await tester.pumpWidget(_buildChart(empty: true));
      await tester.pumpAndSettle();

      expect(noteFr, findsNothing);
    });

    testWidgets('zéro dépense MAIS mensualité de prêt déduite → pas de '
        'mention (le cash-flow affiché ne vaut plus les loyers encaissés)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _PeriodAwareDashboardRepository(),
          const _FakeExpensesRepository(),
          propertyRepo: _FakePropertyRepository([
            _property(
              loanStartDate: DateTime(2020, 1, 1),
              loanMonthlyPaymentOverrideCents: 50000,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(noteFr, findsNothing);
    });
  });
}
