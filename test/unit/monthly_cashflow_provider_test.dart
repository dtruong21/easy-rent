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

import 'package:easyrent/core/finance/expense_recurrence.dart';
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
  required ExpenseCategory category,
  ExpenseNature nature = ExpenseNature.works,
  ExpenseRecurrence recurrence = ExpenseRecurrence.none,
  DateTime? recurrenceEndDate,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: 'p1',
  amountCents: amountCents,
  expenseDate: expenseDate,
  nature: nature,
  category: category,
  periodYear: expenseDate.year,
  recurrence: recurrence,
  recurrenceEndDate: recurrenceEndDate,
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

  group('monthlyCashflowProvider — dépenses récurrentes (FEAT-041d)', () {
    /// Construit le container avec 3 mois de loyers vides et les [expenses]
    /// fournies — seules les dépenses varient d'un test à l'autre.
    Future<List<MonthlyCashflow>> run(List<Expense> expenses) async {
      final rent = [
        for (final monthsAgo in [2, 1, 0])
          MonthlyCollectedRent(
            year: monthDate(monthsAgo).year,
            month: monthDate(monthsAgo).month,
            collectedCents: 0,
            hasPayments: false,
          ),
      ];
      final container = ProviderContainer(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(
            _FakeDashboardRepository(rent),
          ),
          expensesRepositoryProvider.overrideWithValue(
            _FakeExpensesRepository(expenses),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(monthlyCashflowProvider.future);
    }

    test('dépense mensuelle → comptée dans CHAQUE mois affiché, sans qu\'un '
        'seul document supplémentaire existe en base', () async {
      final result = await run([
        _expense(
          id: 'exp-monthly',
          amountCents: 10000,
          expenseDate: monthDate(6),
          category: ExpenseCategory.nonRecoverable,
          recurrence: ExpenseRecurrence.monthly,
        ),
      ]);

      expect(result, hasLength(3));
      for (final month in result) {
        expect(month.nonRecoverableExpenseCents, 10000);
        expect(month.netCents, -10000);
        expect(
          month.hasData,
          isTrue,
          reason: 'une échéance virtuelle fait exister le mois',
        );
      }
    });

    test('dépense trimestrielle → un mois sur trois seulement, et jamais '
        'avant sa date de saisie (pas de rétroactivité)', () async {
      final result = await run([
        _expense(
          id: 'exp-quarterly',
          amountCents: 15000,
          // Première échéance il y a 2 mois : la suivante tombe le mois
          // prochain, donc hors du graphique.
          expenseDate: monthDate(2),
          category: ExpenseCategory.nonRecoverable,
          recurrence: ExpenseRecurrence.quarterly,
        ),
      ]);

      expect(result[0].nonRecoverableExpenseCents, 15000);
      expect(result[1].nonRecoverableExpenseCents, 0);
      expect(result[2].nonRecoverableExpenseCents, 0);
      expect(result[1].hasData, isFalse);
    });

    test(
      'date de fin de récurrence respectée → plus rien après elle',
      () async {
        final result = await run([
          _expense(
            id: 'exp-monthly-ended',
            amountCents: 10000,
            expenseDate: monthDate(6),
            category: ExpenseCategory.nonRecoverable,
            recurrence: ExpenseRecurrence.monthly,
            recurrenceEndDate: monthDate(2),
          ),
        ]);

        expect(result[0].nonRecoverableExpenseCents, 10000);
        expect(result[1].nonRecoverableExpenseCents, 0);
        expect(result[2].nonRecoverableExpenseCents, 0);
      },
    );

    test('dépense ponctuelle ancienne → toujours ignorée (comportement '
        'inchangé, aucune expansion)', () async {
      final result = await run([
        _expense(
          id: 'exp-one-off-old',
          amountCents: 99999,
          expenseDate: monthDate(6),
          category: ExpenseCategory.nonRecoverable,
        ),
      ]);

      expect(result.every((m) => m.nonRecoverableExpenseCents == 0), isTrue);
      expect(result.every((m) => m.hasData == false), isTrue);
    });

    test('dépense récurrente RÉCUPÉRABLE → toujours exclue du cash flow '
        '(refacturée au locataire), la périodicité n\'y change rien', () async {
      final result = await run([
        _expense(
          id: 'exp-recoverable-monthly',
          amountCents: 10000,
          expenseDate: monthDate(6),
          category: ExpenseCategory.recoverable,
          nature: ExpenseNature.condoCharges,
          recurrence: ExpenseRecurrence.monthly,
        ),
      ]);

      expect(result.every((m) => m.nonRecoverableExpenseCents == 0), isTrue);
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
