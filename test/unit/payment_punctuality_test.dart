import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/domain/payment_punctuality.dart';
import 'package:flutter_test/flutter_test.dart';

Payment _pay({
  required DateTime periodStart,
  required DateTime paidAt,
  DateTime? deletedAt,
}) => Payment(
  id: 'p-${paidAt.millisecondsSinceEpoch}',
  leaseId: 'l1',
  landlordId: 'lord1',
  periodStart: periodStart,
  periodEnd: DateTime(periodStart.year, periodStart.month + 1, 0),
  paidAt: paidAt,
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2020, 1, 1),
  updatedAt: DateTime(2020, 1, 1),
  deletedAt: deletedAt,
);

void main() {
  // paymentDay = 5. Échéance mars 2026 = 5 mars ; deadline = 10 mars (grâce 5j).
  test('réglé le jour de la deadline (échéance + 5 j) → à l\'heure', () {
    final k = computePaymentPunctuality([
      _pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 10)),
    ], paymentDay: 5);
    expect(k.total, 1);
    expect(k.onTime, 1);
    expect(k.late, 0);
  });
  test('réglé à échéance + 6 j → en retard', () {
    final k = computePaymentPunctuality([
      _pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 11)),
    ], paymentDay: 5);
    expect(k.onTime, 0);
    expect(k.late, 1);
  });
  test('soft-deleted ignoré', () {
    final k = computePaymentPunctuality([
      _pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 3)),
      _pay(
        periodStart: DateTime(2026, 4, 1),
        paidAt: DateTime(2026, 4, 3),
        deletedAt: DateTime(2026, 5, 1),
      ),
    ], paymentDay: 5);
    expect(k.total, 1);
  });
  test('< 3 paiements → onTimePercent null ; >= 3 → arrondi', () {
    final two = computePaymentPunctuality([
      _pay(periodStart: DateTime(2026, 1, 1), paidAt: DateTime(2026, 1, 3)),
      _pay(periodStart: DateTime(2026, 2, 1), paidAt: DateTime(2026, 2, 3)),
    ], paymentDay: 5);
    expect(two.onTimePercent, isNull);
    final three = computePaymentPunctuality([
      _pay(periodStart: DateTime(2026, 1, 1), paidAt: DateTime(2026, 1, 3)),
      _pay(periodStart: DateTime(2026, 2, 1), paidAt: DateTime(2026, 2, 3)),
      _pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 30)),
    ], paymentDay: 5);
    expect(three.onTimePercent, 67); // 2/3 = 66.7 → 67
  });
  test('aucun paiement → hasPayments false', () {
    expect(computePaymentPunctuality([], paymentDay: 5).hasPayments, isFalse);
  });

  group('combinePaymentPunctuality', () {
    test('somme total et onTime sur plusieurs baux', () {
      final combined = combinePaymentPunctuality(const [
        PaymentPunctuality(total: 3, onTime: 2),
        PaymentPunctuality(total: 3, onTime: 3),
      ]);
      expect(combined.total, 6);
      expect(combined.onTime, 5);
      expect(combined.late, 1);
      expect(combined.onTimePercent, 83); // (5/6*100).round()
    });

    test('liste vide → total 0, hasPayments false, percent null', () {
      final combined = combinePaymentPunctuality(const []);
      expect(combined.total, 0);
      expect(combined.hasPayments, isFalse);
      expect(combined.onTimePercent, isNull);
    });

    test('total agrégé < 3 → onTimePercent null', () {
      final combined = combinePaymentPunctuality(const [
        PaymentPunctuality(total: 1, onTime: 1),
        PaymentPunctuality(total: 1, onTime: 0),
      ]);
      expect(combined.total, 2);
      expect(combined.onTimePercent, isNull);
    });
  });

  group(
    'computePaymentPunctuality — invariant round-trip UTC (régression fuseau)',
    () {
      // En prod, `periodStart`/`paidAt` sont écrits `.toUtc().toIso8601String()`
      // puis relus via `DateTime.parse("…Z")` → DateTime UTC. Lire `.month` sur
      // cet instant décale d'un cran à l'est d'UTC (« 01/08 » France stocké
      // 2026-07-31T22:00Z → mois=juillet → échéance un mois trop tôt → faux
      // retard). Le verdict ne doit PAS dépendre de la forme (locale vs
      // UTC-round-trippée) sous laquelle la même date civile est fournie.
      // Échoue AVANT le fix sous un offset ≠ 0 (ex. Europe/Paris) ; passe après.
      DateTime roundTripUtc(DateTime local) =>
          DateTime.parse(local.toUtc().toIso8601String());

      test('période 01/08, payé 03/08, paymentDay 1 → à l\'heure, IDENTIQUE en '
          'forme locale et UTC-round-trippée', () {
        final periodLocal = DateTime(2026, 8, 1);
        final paidLocal = DateTime(2026, 8, 3);

        final local = computePaymentPunctuality([
          _pay(periodStart: periodLocal, paidAt: paidLocal),
        ], paymentDay: 1);
        final roundTripped = computePaymentPunctuality([
          _pay(
            periodStart: roundTripUtc(periodLocal),
            paidAt: roundTripUtc(paidLocal),
          ),
        ], paymentDay: 1);

        expect(local.onTime, 1);
        expect(local.late, 0);
        expect(
          roundTripped.onTime,
          local.onTime,
          reason:
              'Le verdict ne doit pas dépendre de la forme (locale vs '
              'UTC-round-trippée) de la même date civile.',
        );
        expect(roundTripped.late, local.late);
      });
    },
  );
}
