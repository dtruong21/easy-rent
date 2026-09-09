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
/// - Mensualité de prêt déduite (mois actif), biens sans prêt ignorés, fenêtre
///   du prêt respectée (avant départ / après dernière échéance), une seule
///   requête `list()` landlord-wide pour tous les biens, repli gracieux si
///   les biens échouent à charger
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
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
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

class _FakePropertyRepository implements PropertyRepository {
  _FakePropertyRepository([this._properties = const []]);
  final List<Property> _properties;
  int listCallCount = 0;

  @override
  Future<List<Property>> list() async {
    listCallCount++;
    return _properties;
  }

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

class _ThrowingPropertyRepository implements PropertyRepository {
  @override
  Future<List<Property>> list() async => throw StateError('boom');

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
  String id = 'p1',
  int? loanPrincipalCents,
  int? loanRateBps,
  int? loanInsuranceBps,
  int? loanDurationMonths,
  DateTime? loanStartDate,
  int? loanMonthlyPaymentOverrideCents,
}) => Property(
  id: id,
  landlordId: 'landlord-1',
  name: 'Bien Test',
  address: '1 rue Test',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  loanPrincipalCents: loanPrincipalCents,
  loanRateBps: loanRateBps,
  loanInsuranceBps: loanInsuranceBps,
  loanDurationMonths: loanDurationMonths,
  loanStartDate: loanStartDate,
  loanMonthlyPaymentOverrideCents: loanMonthlyPaymentOverrideCents,
);

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

  group('monthlyCashflowProvider — mensualité de prêt (FIX cash-flow)', () {
    /// Construit le container avec 3 mois de loyers vides et [properties]
    /// fournies — seuls les biens varient d'un test à l'autre, aucune
    /// dépense n'est jamais injectée dans ce groupe.
    ({
      ProviderContainer container,
      ({int year, int month}) twoAgo,
      ({int year, int month}) previous,
      ({int year, int month}) current,
    })
    setUpContainer(List<Property> properties) {
      final twoAgo = monthKey(2);
      final previous = monthKey(1);
      final current = monthKey(0);
      final rent = [
        for (final m in [twoAgo, previous, current])
          MonthlyCollectedRent(
            year: m.year,
            month: m.month,
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
            _FakeExpensesRepository([]),
          ),
          propertyRepositoryProvider.overrideWithValue(
            _FakePropertyRepository(properties),
          ),
        ],
      );
      addTearDown(container.dispose);
      return (
        container: container,
        twoAgo: twoAgo,
        previous: previous,
        current: current,
      );
    }

    test('bien à crédit actif ce mois → mensualité déduite, identique à '
        'computeLoanMonthlyPaymentCents (même moteur que le KPI '
        '« Rentabilité portfolio »)', () async {
      final setup = setUpContainer([
        _property(
          loanPrincipalCents: 20000000,
          loanRateBps: 350,
          loanDurationMonths: 240,
          loanStartDate: DateTime(2020, 1, 1),
        ),
      ]);

      final result = await setup.container.read(monthlyCashflowProvider.future);
      final current = result.last;

      expect(current.year, setup.current.year);
      expect(current.month, setup.current.month);
      expect(current.loanPaymentCents, greaterThan(0));
      expect(current.netCents, -current.loanPaymentCents);
      expect(current.hasData, isTrue);
    });

    test('bien sans prêt → rien déduit', () async {
      final setup = setUpContainer([_property()]);

      final result = await setup.container.read(monthlyCashflowProvider.future);

      expect(result.every((m) => m.loanPaymentCents == 0), isTrue);
      expect(result.every((m) => m.netCents == 0), isTrue);
      expect(result.every((m) => m.hasData == false), isTrue);
    });

    test('mois antérieur au départ du prêt → rien déduit ce mois-là', () async {
      // Départ le mois courant : les 2 mois précédents affichés sont donc
      // strictement antérieurs au départ du prêt.
      final now = DateTime.now();
      final setup = setUpContainer([
        _property(
          loanPrincipalCents: 12000000,
          loanRateBps: 0,
          loanDurationMonths: 12,
          loanStartDate: DateTime(now.year, now.month, 1),
        ),
      ]);

      final result = await setup.container.read(monthlyCashflowProvider.future);

      expect(
        result[0].loanPaymentCents,
        0,
        reason: 'mois -2 : avant le départ',
      );
      expect(
        result[1].loanPaymentCents,
        0,
        reason: 'mois -1 : avant le départ',
      );
      expect(
        result[2].loanPaymentCents,
        greaterThan(0),
        reason: 'mois courant : départ du prêt',
      );
    });

    test('mois postérieur à la dernière échéance → rien déduit', () async {
      // Prêt soldé il y a 1 mois (durée 1 mois, départ il y a 2 mois) : la
      // dernière échéance était le mois -2, donc les mois -1 et courant ne
      // portent plus rien.
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 2, 1);
      final setup = setUpContainer([
        _property(
          loanPrincipalCents: 12000000,
          loanRateBps: 0,
          loanDurationMonths: 1,
          loanStartDate: start,
        ),
      ]);

      final result = await setup.container.read(monthlyCashflowProvider.future);

      expect(
        result[0].loanPaymentCents,
        greaterThan(0),
        reason: 'mois -2 : unique échéance du prêt',
      );
      expect(
        result[1].loanPaymentCents,
        0,
        reason: 'mois -1 : prêt déjà soldé',
      );
      expect(
        result[2].loanPaymentCents,
        0,
        reason: 'mois courant : prêt déjà soldé',
      );
    });

    test('mensualité seule (sans loyer ni dépense) rend le mois négatif, et '
        'le fait exister (hasData=true) — bien vacant à crédit', () async {
      final setup = setUpContainer([
        _property(
          loanStartDate: DateTime(2020, 1, 1),
          loanMonthlyPaymentOverrideCents: 65000,
        ),
      ]);

      final result = await setup.container.read(monthlyCashflowProvider.future);

      for (final m in result) {
        expect(m.collectedRentCents, 0);
        expect(m.nonRecoverableExpenseCents, 0);
        expect(m.loanPaymentCents, 65000);
        expect(m.netCents, -65000);
        expect(m.hasData, isTrue);
      }
    });

    test(
      'une seule requête list() landlord-wide, jamais une par mois',
      () async {
        final fakeProperties = _FakePropertyRepository([
          _property(
            loanPrincipalCents: 20000000,
            loanRateBps: 350,
            loanDurationMonths: 240,
            loanStartDate: DateTime(2020, 1, 1),
          ),
        ]);
        final twoAgo = monthKey(2);
        final previous = monthKey(1);
        final current = monthKey(0);
        final rent = [
          for (final m in [twoAgo, previous, current])
            MonthlyCollectedRent(
              year: m.year,
              month: m.month,
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
              _FakeExpensesRepository([]),
            ),
            propertyRepositoryProvider.overrideWithValue(fakeProperties),
          ],
        );
        addTearDown(container.dispose);

        await container.read(monthlyCashflowProvider.future);

        expect(fakeProperties.listCallCount, 1);
      },
    );

    test('biens indisponibles → cash flow retombe sur loyers/dépenses seuls '
        '(pas de mensualité, pas d\'échec du graphique)', () async {
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
            _FakeExpensesRepository([]),
          ),
          propertyRepositoryProvider.overrideWithValue(
            _ThrowingPropertyRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(monthlyCashflowProvider.future);

      expect(result.length, 1);
      expect(result.first.loanPaymentCents, 0);
      expect(result.first.netCents, 80000);
      expect(result.first.hasData, isTrue);
    });
  });
}
