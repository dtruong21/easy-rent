/// Tests widget de [ChargeRegularizationSection] (FEAT-029 V1.2, FEAT-042).
///
/// Couvre le gate légal — mode de charges effectif, PAS le type de bail
/// (`Lease.canRegularizeCharges`) :
/// - bail nu (`unfurnished`, mode dérivé provisions) → bouton visible
/// - bail meublé/étudiant en provisions (par défaut si `chargeMode` absent)
///   → bouton visible (changement de comportement FEAT-042 assumé — un
///   meublé au provisions EST régularisable)
/// - bail meublé/étudiant en forfait explicite → bouton absent, message
/// - bail mobilité (mode dérivé forfait, quel que soit `chargeMode` fourni
///   par construction du test — le gate lit `canRegularizeCharges`) →
///   bouton absent, message
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/charge_regularization/presentation/widgets/charge_regularization_section.dart';
import 'package:easyrent/features/expenses/data/expenses_repository.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:easyrent/features/leases/domain/charge_mode.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/data/payment_repository.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake PaymentRepository (requis par ChargeRegularizationDialog en aval,
// même si le dialog n'est pas ouvert dans la majorité de ces tests — le
// provider est overridé pour éviter toute dépendance Firebase non
// initialisée en test unitaire).
// ---------------------------------------------------------------------------

class _FakePaymentRepo implements PaymentRepository {
  @override
  Future<List<Payment>> listForLease(String leaseId) async => const [];

  @override
  Future<Payment> getById(String id) async =>
      throw PaymentNotFoundException(id);

  @override
  Future<Payment> create({
    required String leaseId,
    required String landlordId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime paidAt,
    required int rentAmountCents,
    required int chargesAmountCents,
    required PaymentMethod paymentMethod,
    String? notes,
    String? reference,
  }) async => throw UnimplementedError();

  @override
  Future<Payment> update(Payment payment) async => throw UnimplementedError();

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Fake ExpensesRepository (requis par ChargeRegularizationDialog en aval,
// FEAT-041c : le dialog watch recoverableExpensesProvider dès son
// ouverture — override nécessaire pour éviter une dépendance Firebase non
// initialisée en test widget).
// ---------------------------------------------------------------------------

class _FakeExpensesRepo implements ExpensesRepository {
  @override
  Stream<List<Expense>> watchForProperty(String propertyId) =>
      Stream.value(const []);

  @override
  Future<List<Expense>> listForProperty(String propertyId) async => const [];

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
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Lease _makeLease({
  String id = 'lease-1',
  required LeaseType leaseType,
  ChargeMode? chargeMode,
}) => Lease(
  id: id,
  landlordId: 'owner-1',
  propertyId: 'prop-1',
  tenantId: 'tenant-1',
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  status: LeaseStatus.active,
  leaseType: leaseType,
  chargeMode: chargeMode,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Widget _buildSection(Lease lease) {
  return ProviderScope(
    overrides: [
      paymentRepositoryProvider.overrideWithValue(_FakePaymentRepo()),
      expensesRepositoryProvider.overrideWithValue(_FakeExpensesRepo()),
    ],
    child: MaterialApp(
      // AppTheme.light requis : StatusPill (utilisé dans le résumé du solde
      // du dialog ouvert par cette section) lit l'extension AppColors —
      // absente du ThemeData par défaut de MaterialApp.
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
      home: Scaffold(
        body: ChargeRegularizationSection(
          lease: lease,
          landlordFullName: 'Marie Martin',
          landlordAddress: '1 rue de Paris, 75001 Paris',
          tenantFullName: 'Jean Dupont',
          tenantFirstName: 'Jean',
          propertyAddress: '2 rue de Lyon, 69001 Lyon',
          tenantEmail: 'jean.dupont@example.com',
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChargeRegularizationSection — bail nu (unfurnished)', () {
    testWidgets('bouton "Régularisation annuelle des charges" visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSection(_makeLease(leaseType: LeaseType.unfurnished)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('btn_charge_regularization')),
        findsOneWidget,
      );
    });

    testWidgets('message "forfait non applicable" ABSENT', (tester) async {
      await tester.pumpWidget(
        _buildSection(_makeLease(leaseType: LeaseType.unfurnished)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('text_charge_regularization_not_applicable')),
        findsNothing,
      );
    });

    testWidgets('tap sur le bouton ouvre le dialog de régularisation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSection(_makeLease(leaseType: LeaseType.unfurnished)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_charge_regularization')));
      await tester.pumpAndSettle();

      expect(find.text('Régularisation annuelle des charges'), findsWidgets);
      expect(
        find.byKey(const Key('btn_charge_regularization_generate')),
        findsOneWidget,
      );
    });
  });

  group('ChargeRegularizationSection — bail meublé (furnished) en PROVISIONS '
      '(FEAT-042 : défaut si chargeMode absent)', () {
    testWidgets('bouton "Régularisation annuelle des charges" visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSection(
          _makeLease(
            leaseType: LeaseType.furnished,
            chargeMode: ChargeMode.provisions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('btn_charge_regularization')),
        findsOneWidget,
      );
    });

    testWidgets(
      'chargeMode absent (legacy pré-042) → visible aussi (dérivation '
      'par défaut provisions)',
      (tester) async {
        await tester.pumpWidget(
          _buildSection(_makeLease(leaseType: LeaseType.furnished)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_charge_regularization')),
          findsOneWidget,
        );
      },
    );
  });

  group('ChargeRegularizationSection — bail meublé (furnished) en FORFAIT', () {
    testWidgets('bouton "Régularisation annuelle des charges" ABSENT', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSection(
          _makeLease(
            leaseType: LeaseType.furnished,
            chargeMode: ChargeMode.forfait,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_charge_regularization')), findsNothing);
    });

    testWidgets('message informatif "forfait non applicable" visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSection(
          _makeLease(
            leaseType: LeaseType.furnished,
            chargeMode: ChargeMode.forfait,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('text_charge_regularization_not_applicable')),
        findsOneWidget,
      );
      expect(
        find.textContaining('ne donne pas lieu à régularisation'),
        findsOneWidget,
      );
    });
  });

  group(
    'ChargeRegularizationSection — bail mobilité (forfait obligatoire)',
    () {
      testWidgets('bouton ABSENT (mode dérivé forfait, loi ELAN art. 25-18)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildSection(_makeLease(leaseType: LeaseType.mobility)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_charge_regularization')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('text_charge_regularization_not_applicable')),
          findsOneWidget,
        );
      });
    },
  );

  group(
    'ChargeRegularizationSection — bail étudiant (student) en PROVISIONS',
    () {
      testWidgets('bouton visible', (tester) async {
        await tester.pumpWidget(
          _buildSection(
            _makeLease(
              leaseType: LeaseType.student,
              chargeMode: ChargeMode.provisions,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('btn_charge_regularization')),
          findsOneWidget,
        );
      });
    },
  );

  group('ChargeRegularizationSection — bail étudiant (student) en FORFAIT', () {
    testWidgets('bouton ABSENT', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          _makeLease(
            leaseType: LeaseType.student,
            chargeMode: ChargeMode.forfait,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_charge_regularization')), findsNothing);
      expect(
        find.byKey(const Key('text_charge_regularization_not_applicable')),
        findsOneWidget,
      );
    });
  });
}
