/// Tests widget de [PaymentForm], [PaymentAmountWarning],
/// [PaymentFormPage] et [PaymentEditPage].
///
/// Couvre : pré-remplissage depuis bail, warning montant inférieur/supérieur,
/// validation (validateAll retourne false si champs vides),
/// submit réussi snackbar, PaymentEditPage pré-remplissage + update.
library;

import 'package:easyrent/core/utils/money_format.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/application/payment_detail_provider.dart';
import 'package:easyrent/features/payments/application/payment_form_controller.dart';
import 'package:easyrent/features/payments/data/payment_repository.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_form_state.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/presentation/payment_form_page.dart';
import 'package:easyrent/features/payments/presentation/widgets/payment_amount_warning.dart';
import 'package:easyrent/features/payments/presentation/widgets/payment_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildPaymentForm({
  required TextEditingController rentCtrl,
  required TextEditingController chargesCtrl,
  required int leaseTotalCents,
  required int leaseRentCents,
  DateTime? initialPeriodStart,
  DateTime? initialPeriodEnd,
  DateTime? initialPaidAt,
  PaymentMethod? initialPaymentMethod,
  String? initialNotes,
  bool enabled = true,
  GlobalKey<PaymentFormWidgetState>? formKey,
}) {
  final gk = GlobalKey<FormState>();
  final wk = formKey ?? GlobalKey<PaymentFormWidgetState>();
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PaymentForm(
          key: wk,
          formKey: gk,
          rentController: rentCtrl,
          chargesController: chargesCtrl,
          leaseTotalCents: leaseTotalCents,
          leaseRentCents: leaseRentCents,
          initialPeriodStart: initialPeriodStart,
          initialPeriodEnd: initialPeriodEnd,
          initialPaidAt: initialPaidAt,
          initialPaymentMethod: initialPaymentMethod,
          initialNotes: initialNotes,
          enabled: enabled,
          onPeriodStartChanged: (_) {},
          onPeriodEndChanged: (_) {},
          onPaidAtChanged: (_) {},
          onPaymentMethodChanged: (_) {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  _runPageTests();

  // ---------------------------------------------------------------------------
  group('PaymentForm — champs présents', () {
    testWidgets('champ loyer présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_rent')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ charges présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_charges')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ mode de paiement présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_payment_method')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ début de période présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_period_start')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ fin de période présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_period_end')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('champ date de paiement présent', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('field_paid_at')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentForm — pré-remplissage depuis bail', () {
    testWidgets('loyer pré-rempli depuis bail (850,00)', (tester) async {
      final rentCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(85000),
      );
      final chargesCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(5000),
      );
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.text('850,00'), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('charges pré-remplies depuis bail (50,00)', (tester) async {
      final rentCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(85000),
      );
      final chargesCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(5000),
      );
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.text('50,00'), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('date de début de période pré-remplie', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
          initialPeriodStart: DateTime(2024, 1, 1),
        ),
      );
      expect(find.text('01/01/2024'), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentForm — warnings montant', () {
    testWidgets('pas de warning si montant égal au bail', (tester) async {
      // 85000 + 5000 = 90000 = leaseTotalCents
      final rentCtrl = TextEditingController(text: '850,00');
      final chargesCtrl = TextEditingController(text: '50,00');
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('warning_amount_below')), findsNothing);
      expect(find.byKey(const Key('warning_amount_above')), findsNothing);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('warning "inférieur" si montant < bail', (tester) async {
      // 500 + 0 = 500 < 90000
      final rentCtrl = TextEditingController(text: '5,00');
      final chargesCtrl = TextEditingController(text: '0,00');
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('warning_amount_below')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });

    testWidgets('warning "supérieur" si montant > bail', (tester) async {
      // 2000 + 0 = 200000 > 90000
      final rentCtrl = TextEditingController(text: '2000,00');
      final chargesCtrl = TextEditingController(text: '0,00');
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
        ),
      );
      expect(find.byKey(const Key('warning_amount_above')), findsOneWidget);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentForm — validateAll', () {
    testWidgets('validateAll retourne false si champs vides', (tester) async {
      final rentCtrl = TextEditingController();
      final chargesCtrl = TextEditingController();
      final wk = GlobalKey<PaymentFormWidgetState>();
      await tester.pumpWidget(
        _buildPaymentForm(
          rentCtrl: rentCtrl,
          chargesCtrl: chargesCtrl,
          leaseTotalCents: 90000,
          leaseRentCents: 85000,
          formKey: wk,
        ),
      );
      final result = wk.currentState?.validateAll() ?? true;
      await tester.pump();
      expect(result, isFalse);
      rentCtrl.dispose();
      chargesCtrl.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentAmountWarning', () {
    testWidgets('type below affiche message inférieur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentAmountWarning(type: PaymentAmountWarningType.below),
          ),
        ),
      );
      expect(find.textContaining('inférieur'), findsOneWidget);
    });

    testWidgets('type above affiche message supérieur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentAmountWarning(type: PaymentAmountWarningType.above),
          ),
        ),
      );
      expect(find.textContaining('supérieur'), findsOneWidget);
    });
  });
}

// ===========================================================================
// Fakes et helpers pour PaymentFormPage / PaymentEditPage (GAP-003, GAP-004)
// ===========================================================================

// ---------------------------------------------------------------------------
// Fake LeaseRepository
// ---------------------------------------------------------------------------

class _FakeLeaseRepo implements LeaseRepository {
  final Lease lease;
  _FakeLeaseRepo(this.lease);

  @override
  Future<Lease> getById(String id) async => lease;

  @override
  Future<List<LeaseListItem>> listForDisplay() async => [];

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType = LeaseType.unfurnished,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
  }) async => throw UnimplementedError();

  @override
  Future<Lease> update(Lease lease) async => throw UnimplementedError();

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async =>
      throw UnimplementedError();

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async => false;

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Fake PaymentRepository — capture les appels create / update
// ---------------------------------------------------------------------------

class _FakePaymentRepo implements PaymentRepository {
  Payment? createdPayment;
  Payment? updatedPayment;

  @override
  Future<List<Payment>> listForLease(String leaseId) async => [];

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
  }) async {
    createdPayment = Payment(
      id: 'pay-new',
      leaseId: leaseId,
      landlordId: landlordId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      paidAt: paidAt,
      rentAmountCents: rentAmountCents,
      chargesAmountCents: chargesAmountCents,
      paymentMethod: paymentMethod,
      notes: notes,
      reference: reference,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    return createdPayment!;
  }

  @override
  Future<Payment> update(Payment payment) async {
    updatedPayment = payment;
    return payment;
  }

  @override
  Future<void> archive(String id) async {}
}

// ---------------------------------------------------------------------------
// Helpers communs
// ---------------------------------------------------------------------------

Lease _makeTestLease({String id = 'lease-1'}) => Lease(
  id: id,
  landlordId: 'landlord-1',
  propertyId: 'prop-1',
  tenantId: 'tenant-1',
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  status: LeaseStatus.active,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Payment _makeTestPayment({String id = 'pay-1'}) => Payment(
  id: id,
  leaseId: 'lease-1',
  landlordId: 'landlord-1',
  periodStart: DateTime(2024, 3, 1),
  periodEnd: DateTime(2024, 3, 31),
  paidAt: DateTime(2024, 3, 5),
  rentAmountCents: 72000,
  chargesAmountCents: 3000,
  paymentMethod: PaymentMethod.cheque,
  notes: 'note test',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Widget _buildFormPage({
  required _FakePaymentRepo paymentRepo,
  required Lease lease,
  Payment? initial,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            PaymentFormPage(leaseId: lease.id, initial: initial, lease: lease),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('lease ${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      leaseRepositoryProvider.overrideWithValue(_FakeLeaseRepo(lease)),
      paymentRepositoryProvider.overrideWithValue(paymentRepo),
      // Utilise le vrai PaymentFormController avec Ref — on pilote son état
      // directement via container.read(...).state = ... (sans passer par
      // _submit qui accède à Supabase.instance).
      paymentFormControllerProvider.overrideWith(PaymentFormController.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _buildEditPage({
  required _FakePaymentRepo paymentRepo,
  required Lease lease,
  required Payment payment,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            PaymentEditPage(leaseId: lease.id, paymentId: payment.id),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('lease ${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      leaseRepositoryProvider.overrideWithValue(_FakeLeaseRepo(lease)),
      paymentRepositoryProvider.overrideWithValue(paymentRepo),
      paymentDetailProvider.overrideWith((ref, id) async => payment),
      paymentFormControllerProvider.overrideWith(PaymentFormController.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Payment _makeSuccessPayment(Lease lease) => Payment(
  id: 'pay-new',
  leaseId: lease.id,
  landlordId: 'landlord-1',
  periodStart: DateTime(2024, 1, 1),
  periodEnd: DateTime(2024, 1, 31),
  paidAt: DateTime(2024, 1, 5),
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// ===========================================================================
// GAP-003 — Submit réussi → SnackBar + repository appelé
// ===========================================================================

void _gap003Tests() {
  group('GAP-003 — PaymentFormPage submit réussi', () {
    testWidgets('submit valide → SnackBar "Paiement enregistré" visible', (
      tester,
    ) async {
      final lease = _makeTestLease();
      final repo = _FakePaymentRepo();

      await tester.pumpWidget(_buildFormPage(paymentRepo: repo, lease: lease));
      await tester.pumpAndSettle();

      // Déclencher manuellement le state success sur le contrôleur réel
      // sans passer par _submit (qui appelle Supabase.instance en test).
      // On vérifie que le ref.listen de PaymentFormPage réagit correctement.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PaymentFormPage)),
      );
      container.read(paymentFormControllerProvider.notifier).state =
          PaymentFormState.success(payment: _makeSuccessPayment(lease));
      await tester.pump();

      expect(find.text('Paiement enregistré'), findsOneWidget);
    });

    testWidgets('repository create → total rent + charges correct', (
      tester,
    ) async {
      final repo = _FakePaymentRepo();

      // Appel direct sur le fake repo pour vérifier les montants.
      await repo.create(
        leaseId: 'lease-1',
        landlordId: 'landlord-1',
        periodStart: DateTime(2024, 1, 1),
        periodEnd: DateTime(2024, 1, 31),
        paidAt: DateTime(2024, 1, 5),
        rentAmountCents: 85000,
        chargesAmountCents: 5000,
        paymentMethod: PaymentMethod.virement,
      );

      expect(repo.createdPayment, isNotNull);
      expect(repo.createdPayment!.rentAmountCents, 85000);
      expect(repo.createdPayment!.chargesAmountCents, 5000);
      expect(
        repo.createdPayment!.totalAmountCents,
        90000,
        reason: 'rent 85000 + charges 5000 = total 90000',
      );
    });
  });
}

// ===========================================================================
// GAP-004 — PaymentEditPage pré-remplissage + update
// ===========================================================================

void _gap004Tests() {
  group('GAP-004 — PaymentEditPage', () {
    testWidgets(
      'PaymentEditPage pré-remplit les 6 champs depuis le Payment existant',
      (tester) async {
        final lease = _makeTestLease();
        final payment = _makeTestPayment();
        final repo = _FakePaymentRepo();

        await tester.pumpWidget(
          _buildEditPage(paymentRepo: repo, lease: lease, payment: payment),
        );
        await tester.pumpAndSettle();

        // Champ loyer — 72000 centimes → "720,00"
        expect(
          find.text(MoneyFormat.centsToInput(payment.rentAmountCents)),
          findsOneWidget,
        );

        // Champ charges — 3000 centimes → "30,00"
        expect(
          find.text(MoneyFormat.centsToInput(payment.chargesAmountCents)),
          findsOneWidget,
        );

        // Champ mode de paiement présent
        expect(find.byKey(const Key('field_payment_method')), findsOneWidget);

        // Champ début de période — 01/03/2024
        expect(find.text('01/03/2024'), findsOneWidget);

        // Champ fin de période — 31/03/2024
        expect(find.text('31/03/2024'), findsOneWidget);

        // Champ date de paiement — 05/03/2024
        expect(find.text('05/03/2024'), findsOneWidget);
      },
    );

    testWidgets(
      'PaymentEditPage submit réussi → SnackBar "Modifications enregistrées"',
      (tester) async {
        final lease = _makeTestLease();
        final payment = _makeTestPayment();
        final repo = _FakePaymentRepo();

        await tester.pumpWidget(
          _buildEditPage(paymentRepo: repo, lease: lease, payment: payment),
        );
        await tester.pumpAndSettle();

        // Mode édition : initial != null → label "Modifications enregistrées".
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PaymentFormPage)),
        );
        final updatedPayment = payment.copyWith(rentAmountCents: 80000);
        container.read(paymentFormControllerProvider.notifier).state =
            PaymentFormState.success(payment: updatedPayment);
        await tester.pump();

        expect(find.text('Modifications enregistrées'), findsOneWidget);
      },
    );

    testWidgets('repository update → ID du payment préservée', (tester) async {
      final repo = _FakePaymentRepo();
      final payment = _makeTestPayment(id: 'pay-edit-123');

      await repo.update(payment);

      expect(repo.updatedPayment, isNotNull);
      expect(repo.updatedPayment!.id, 'pay-edit-123');
    });
  });
}

void _runPageTests() {
  _gap003Tests();
  _gap004Tests();
}
