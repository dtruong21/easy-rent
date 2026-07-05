/// Tests widget de [PaymentListSection].
///
/// Couvre : tri period_start DESC, bouton "Ajouter" désactivé si bail clôturé,
/// liste vide → état placeholder.
library;

import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/data/payment_repository.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/presentation/widgets/payment_list_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fakes
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
    int nonRecoverableChargesCents = 0,
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

class _FakePaymentRepo implements PaymentRepository {
  final List<Payment> payments;
  _FakePaymentRepo(this.payments);

  @override
  Future<List<Payment>> listForLease(String leaseId) async {
    final result = payments.where((p) => p.leaseId == leaseId).toList()
      ..sort((a, b) => b.periodStart.compareTo(a.periodStart));
    return result;
  }

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
// Helpers
// ---------------------------------------------------------------------------

Lease _makeLease({LeaseStatus status = LeaseStatus.active}) => Lease(
  id: 'lease-1',
  landlordId: 'landlord-1',
  propertyId: 'prop-1',
  tenantId: 'tenant-1',
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  status: status,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Payment _makePayment({
  required String id,
  required DateTime periodStart,
  required DateTime periodEnd,
}) => Payment(
  id: id,
  leaseId: 'lease-1',
  landlordId: 'landlord-1',
  periodStart: periodStart,
  periodEnd: periodEnd,
  paidAt: DateTime(2024, 1, 5),
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Widget _buildSection({required Lease lease, required List<Payment> payments}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: SingleChildScrollView(
            child: PaymentListSection(leaseId: lease.id),
          ),
        ),
      ),
      GoRoute(
        path: '/leases/:id/payments/new',
        builder: (_, state) =>
            Scaffold(body: Text('new payment ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id/payments/:pid/edit',
        builder: (_, state) =>
            Scaffold(body: Text('edit payment ${state.pathParameters['pid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      leaseRepositoryProvider.overrideWithValue(_FakeLeaseRepo(lease)),
      paymentRepositoryProvider.overrideWithValue(_FakePaymentRepo(payments)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PaymentListSection', () {
    // -----------------------------------------------------------------------
    testWidgets('titre "Paiements" visible', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(_buildSection(lease: lease, payments: []));
      await tester.pumpAndSettle();
      expect(find.text('Paiements'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    testWidgets('liste vide → placeholder visible', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(_buildSection(lease: lease, payments: []));
      await tester.pumpAndSettle();
      // Hint "Aucun paiement" visible
      expect(find.textContaining('Aucun paiement'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    testWidgets('liste non vide → tiles visibles', (tester) async {
      final lease = _makeLease();
      final payments = [
        _makePayment(
          id: 'pay-1',
          periodStart: DateTime(2024, 1, 1),
          periodEnd: DateTime(2024, 1, 31),
        ),
      ];
      await tester.pumpWidget(_buildSection(lease: lease, payments: payments));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_tile_pay-1')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    testWidgets('tri period_start DESC — plus récent en premier', (
      tester,
    ) async {
      final lease = _makeLease();
      final payments = [
        _makePayment(
          id: 'pay-old',
          periodStart: DateTime(2024, 1, 1),
          periodEnd: DateTime(2024, 1, 31),
        ),
        _makePayment(
          id: 'pay-new',
          periodStart: DateTime(2024, 3, 1),
          periodEnd: DateTime(2024, 3, 31),
        ),
      ];
      await tester.pumpWidget(_buildSection(lease: lease, payments: payments));
      await tester.pumpAndSettle();

      // Les deux tiles sont présentes
      expect(find.byKey(const Key('payment_tile_pay-old')), findsOneWidget);
      expect(find.byKey(const Key('payment_tile_pay-new')), findsOneWidget);

      // pay-new doit apparaître avant pay-old dans le widget tree
      final tileOld = tester.getTopLeft(
        find.byKey(const Key('payment_tile_pay-old')),
      );
      final tileNew = tester.getTopLeft(
        find.byKey(const Key('payment_tile_pay-new')),
      );
      expect(tileNew.dy, lessThan(tileOld.dy));
    });

    // -----------------------------------------------------------------------
    testWidgets('bail actif → bouton "Ajouter" actif', (tester) async {
      final lease = _makeLease(status: LeaseStatus.active);
      await tester.pumpWidget(_buildSection(lease: lease, payments: []));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_add_payment')),
      );
      expect(btn.onPressed, isNotNull);
    });

    // -----------------------------------------------------------------------
    testWidgets('bail clôturé → bouton "Ajouter" désactivé', (tester) async {
      final lease = _makeLease(status: LeaseStatus.terminated);
      await tester.pumpWidget(_buildSection(lease: lease, payments: []));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_add_payment')),
      );
      expect(btn.onPressed, isNull);
    });

    // -----------------------------------------------------------------------
    // GAP-001 — bail archivé désactive aussi le bouton
    testWidgets(
      'bail archivé → bouton "Ajouter" désactivé + tooltip "Ce bail est clôturé."',
      (tester) async {
        final lease = _makeLease(status: LeaseStatus.archived);
        await tester.pumpWidget(_buildSection(lease: lease, payments: []));
        await tester.pumpAndSettle();

        final btn = tester.widget<FilledButton>(
          find.byKey(const Key('btn_add_payment')),
        );
        expect(btn.onPressed, isNull);

        final tooltip = tester.widget<Tooltip>(
          find.ancestor(
            of: find.byKey(const Key('btn_add_payment')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, 'Ce bail est clôturé.');
      },
    );

    // -----------------------------------------------------------------------
    testWidgets('bail clôturé → message "bail clôturé" dans placeholder vide', (
      tester,
    ) async {
      final lease = _makeLease(status: LeaseStatus.terminated);
      await tester.pumpWidget(_buildSection(lease: lease, payments: []));
      await tester.pumpAndSettle();
      expect(find.textContaining('clôturé'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    testWidgets('tap bouton "Ajouter" navigue vers /payments/new', (
      tester,
    ) async {
      final lease = _makeLease(status: LeaseStatus.active);
      await tester.pumpWidget(_buildSection(lease: lease, payments: []));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_add_payment')));
      await tester.pumpAndSettle();

      expect(find.text('new payment lease-1'), findsOneWidget);
    });
  });
}
