/// Période proposée par défaut pour un nouveau paiement (#197).
library;

import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/domain/suggested_payment_period.dart';
import 'package:flutter_test/flutter_test.dart';

Lease _lease({required DateTime start, DateTime? end}) => Lease(
  id: 'lease-1',
  landlordId: 'landlord-1',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  startDate: start,
  endDate: end,
  status: LeaseStatus.active,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Payment _payment(DateTime start, DateTime end) => Payment(
  id: 'pay-${start.toIso8601String()}',
  leaseId: 'lease-1',
  landlordId: 'landlord-1',
  periodStart: start,
  periodEnd: end,
  paidAt: start,
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  final now = DateTime(2026, 10, 4);

  test('aucun paiement : le mois courant entier', () {
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2025, 1, 1)),
      payments: const [],
      now: now,
    );
    expect(p?.start, DateTime(2026, 10, 1));
    expect(p?.end, DateTime(2026, 10, 31));
  });

  test('aucun paiement, bail démarré ce mois-ci : à partir du démarrage', () {
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2026, 10, 15)),
      payments: const [],
      now: now,
    );
    expect(p?.start, DateTime(2026, 10, 15));
    expect(p?.end, DateTime(2026, 10, 31));
  });

  test('aucun paiement, bail qui démarre le mois prochain : ce mois-là', () {
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2026, 11, 1)),
      payments: const [],
      now: now,
    );
    expect(p?.start, DateTime(2026, 11, 1));
    expect(p?.end, DateTime(2026, 11, 30));
  });

  test('paiements : le mois qui suit le dernier, quel que soit l\'ordre', () {
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2025, 1, 1)),
      payments: [
        _payment(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
        _payment(DateTime(2026, 7, 1), DateTime(2026, 7, 31)),
      ],
      now: now,
    );
    expect(p?.start, DateTime(2026, 10, 1));
    expect(p?.end, DateTime(2026, 10, 31));
  });

  test('dernier paiement en cours de mois : du lendemain à la fin du mois', () {
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2026, 3, 15)),
      payments: [_payment(DateTime(2026, 3, 15), DateTime(2026, 4, 14))],
      now: now,
    );
    expect(p?.start, DateTime(2026, 4, 15));
    expect(p?.end, DateTime(2026, 4, 30));
  });

  test('fin de période en UTC (Firestore) : jour local, pas de décalage', () {
    // 31/12 à minuit Paris = 30/12 23:00 UTC.
    final lastEnd = DateTime(2026, 12, 31).toUtc();
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2025, 1, 1)),
      payments: [_payment(DateTime(2026, 12, 1).toUtc(), lastEnd)],
      now: now,
    );
    expect(p?.start, DateTime(2027, 1, 1));
    expect(p?.end, DateTime(2027, 1, 31));
  });

  test('fin bornée par la fin du bail', () {
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2025, 1, 1), end: DateTime(2026, 10, 20)),
      payments: const [],
      now: now,
    );
    expect(p?.start, DateTime(2026, 10, 1));
    expect(p?.end, DateTime(2026, 10, 20));
  });

  test('bail terminé avant la période proposée : rien à proposer', () {
    final p = suggestedPaymentPeriod(
      lease: _lease(start: DateTime(2025, 1, 1), end: DateTime(2026, 9, 30)),
      payments: [_payment(DateTime(2026, 9, 1), DateTime(2026, 9, 30))],
      now: now,
    );
    expect(p, isNull);
  });
}
