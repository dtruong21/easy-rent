/// Tests de [monthlyCashflowProvider] — agrégation cash flow réel mensuel.
///
/// Couvre :
/// - Mois positif (loyers > dépenses non récupérables)
/// - Mois négatif (dépenses non récupérables > loyers)
/// - Mois sans donnée (aucun paiement ni dépense)
/// - Dépenses récupérables exclues du calcul (refacturées au locataire)
/// - Toute nature non récupérable compte (pas restreint aux 3 natures de
///   `groupRealCharges` — pas de prévisionnel à protéger d'un double
///   comptage ici, cf. doc de tête de `MonthlyCashflow`)
/// - Une seule requête `listAllForLandlord`, jamais une par mois
/// - Repli gracieux sur le seul encaissé si les dépenses échouent à charger
library;

import 'package:easyrent/features/dashboard/application/dashboard_provider.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/monthly_cashflow.dart';
import 'package:easyrent/features/expenses/data/expenses_repository.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository(this._rent);
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
  _FakeExpensesRepository(this._expenses);
  final List<Expense> _expenses;
  int listAllForLandlordCallCount = 0;

  @override
  Future<List<Expense>> listAllForLandlord() async {
    listAllForLandlordCallCount++;
    return _expenses;
  }

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
    String? documentId,
    String? notes,
  }) async => throw UnimplementedError();
  @override
  Future<Expense> update(Expense expense) async => throw UnimplementedError();
  @override
  Future<void> archive(String id) async => throw UnimplementedError();
}

class _ThrowingExpensesRepository implements ExpensesRepository {
  @override
  Future<List<Expense>> listAllForLandlord() async => throw StateError('boom');

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
  required ExpenseCategory category,
  ExpenseNature nature = ExpenseNature.works,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: 'p1',
  amountCents: amountCents,
  expenseDate: expenseDate,
  nature: nature,
  category: category,
  periodYear: expenseDate.year,
  createdAt: expenseDate,
  updatedAt: expenseDate,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final now = DateTime.now();
  DateTime monthDate(int monthsAgo, [int day = 15]) =>
      DateTime(now.year, now.month - monthsAgo, day);
  ({int year, int month}) monthKey(int monthsAgo) {
    final d = monthDate(monthsAgo);
    return (year: d.year, month: d.month);
  }

  group('monthlyCashflowProvider — signe et données', () {
    test('mois positif (loyers > dépenses), négatif (dépenses > loyers) et '
        'sans donnée cohabitent correctement', () async {
      final current = monthKey(0);
      final previous = monthKey(1);
      final twoMonthsAgo = monthKey(2);

      final rent = [
        MonthlyCollectedRent(
          year: twoMonthsAgo.year,
          month: twoMonthsAgo.month,
          collectedCents: 50000,
          hasPayments: true,
        ),
        MonthlyCollectedRent(
          year: previous.year,
          month: previous.month,
          collectedCents: 0,
          hasPayments: false,
        ),
        MonthlyCollectedRent(
          year: current.year,
          month: current.month,
          collectedCents: 80000,
          hasPayments: true,
        ),
      ];

      final expenses = [
        // Réduit le mois courant sans le faire passer sous zéro.
        _expense(
          id: 'exp-current-nonrecoverable',
          amountCents: 20000,
          expenseDate: monthDate(0),
          category: ExpenseCategory.nonRecoverable,
        ),
        // Récupérable : DOIT être exclue (refacturée au locataire).
        _expense(
          id: 'exp-current-recoverable',
          amountCents: 999999,
          expenseDate: monthDate(0),
          category: ExpenseCategory.recoverable,
          nature: ExpenseNature.condoCharges,
        ),
        // Grosse dépense « travaux » (nature hors des 3 retenues par
        // `groupRealCharges`) qui fait passer le mois à 2 mois en négatif —
        // vérifie que ce graphique ne restreint PAS aux 3 natures.
        _expense(
          id: 'exp-2ago-works',
          amountCents: 200000,
          expenseDate: monthDate(2),
          category: ExpenseCategory.nonRecoverable,
          nature: ExpenseNature.works,
        ),
      ];

      final expensesRepo = _FakeExpensesRepository(expenses);
      final container = ProviderContainer(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(
            _FakeDashboardRepository(rent),
          ),
          expensesRepositoryProvider.overrideWithValue(expensesRepo),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(monthlyCashflowProvider.future);

      expect(result.length, 3);

      final twoAgoResult = result[0];
      expect(twoAgoResult.year, twoMonthsAgo.year);
      expect(twoAgoResult.month, twoMonthsAgo.month);
      expect(twoAgoResult.collectedRentCents, 50000);
      expect(twoAgoResult.nonRecoverableExpenseCents, 200000);
      expect(twoAgoResult.netCents, -150000);
      expect(twoAgoResult.netCents, lessThan(0));
      expect(twoAgoResult.hasData, isTrue);

      final previousResult = result[1];
      expect(previousResult.collectedRentCents, 0);
      expect(previousResult.nonRecoverableExpenseCents, 0);
      expect(previousResult.netCents, 0);
      expect(
        previousResult.hasData,
        isFalse,
        reason: 'aucun loyer ni dépense ce mois-ci',
      );

      final currentResult = result[2];
      expect(currentResult.collectedRentCents, 80000);
      // La dépense récupérable (999999) est exclue — seule la
      // non-récupérable (20000) compte.
      expect(currentResult.nonRecoverableExpenseCents, 20000);
      expect(currentResult.netCents, 60000);
      expect(currentResult.netCents, greaterThan(0));
      expect(currentResult.hasData, isTrue);

      // Une seule requête landlord-wide pour toute la période affichée,
      // jamais une par mois.
      expect(expensesRepo.listAllForLandlordCallCount, 1);
    });
  });

  group('monthlyCashflowProvider — repli gracieux', () {
    test(
      'dépenses indisponibles → cash flow retombe sur le seul encaissé',
      () async {
        final current = monthKey(0);
        final rent = [
          MonthlyCollectedRent(
            year: current.year,
            month: current.month,
            collectedCents: 80000,
            hasPayments: true,
          ),
        ];

        final container = ProviderContainer(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(
              _FakeDashboardRepository(rent),
            ),
            expensesRepositoryProvider.overrideWithValue(
              _ThrowingExpensesRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(monthlyCashflowProvider.future);

        expect(result.length, 1);
        expect(result.first.collectedRentCents, 80000);
        expect(result.first.nonRecoverableExpenseCents, 0);
        expect(result.first.netCents, 80000);
        expect(result.first.hasData, isTrue);
      },
    );
  });
}
