/// Tests de [sumChargeProvisionsForPeriod] (FEAT-029 V1.2).
///
/// Couvre :
/// - somme correcte sur des paiements qui recouvrent la période
/// - exclusion des paiements hors période (avant / après)
/// - recouvrement partiel aux bornes (inclusion totale, pas de proratisation)
/// - piège de fuseau horaire : comparaison de `DateTime` UTC (tel que relu
///   depuis Firestore) contre une période de référence en heure locale —
///   même piège documenté dans `lease_lateness_test.dart`.
library;

import 'package:easyrent/features/charge_regularization/application/charge_provisions_calculator.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Payment _makePayment({
  String id = 'pay-1',
  required DateTime periodStart,
  required DateTime periodEnd,
  int chargesAmountCents = 5000,
}) => Payment(
  id: id,
  leaseId: 'lease-1',
  landlordId: 'landlord-1',
  periodStart: periodStart,
  periodEnd: periodEnd,
  paidAt: periodStart,
  rentAmountCents: 80000,
  chargesAmountCents: chargesAmountCents,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('sumChargeProvisionsForPeriod — cas de base', () {
    test('somme correcte de plusieurs paiements dans la période', () {
      final payments = [
        _makePayment(
          id: 'p1',
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 1, 31),
          chargesAmountCents: 5000,
        ),
        _makePayment(
          id: 'p2',
          periodStart: DateTime(2025, 2, 1),
          periodEnd: DateTime(2025, 2, 28),
          chargesAmountCents: 5000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 10000);
    });

    test('12 mensualités de 100,00 € de charges → 1200,00 €', () {
      final payments = List.generate(
        12,
        (i) => _makePayment(
          id: 'p$i',
          periodStart: DateTime(2025, i + 1, 1),
          periodEnd: DateTime(2025, i + 1, 28),
          chargesAmountCents: 10000,
        ),
      );
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 120000);
    });

    test('liste de paiements vide → 0', () {
      final total = sumChargeProvisionsForPeriod(
        payments: const [],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group('sumChargeProvisionsForPeriod — exclusion hors période', () {
    test('paiement entièrement avant la période → exclu', () {
      final payments = [
        _makePayment(
          periodStart: DateTime(2024, 1, 1),
          periodEnd: DateTime(2024, 1, 31),
          chargesAmountCents: 5000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });

    test('paiement entièrement après la période → exclu', () {
      final payments = [
        _makePayment(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          chargesAmountCents: 5000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });

    test(
      'mix paiements dans/hors période → seuls ceux dans la période comptent',
      () {
        final payments = [
          _makePayment(
            id: 'before',
            periodStart: DateTime(2024, 12, 1),
            periodEnd: DateTime(2024, 12, 31),
            chargesAmountCents: 9999,
          ),
          _makePayment(
            id: 'inside',
            periodStart: DateTime(2025, 6, 1),
            periodEnd: DateTime(2025, 6, 30),
            chargesAmountCents: 5000,
          ),
          _makePayment(
            id: 'after',
            periodStart: DateTime(2026, 2, 1),
            periodEnd: DateTime(2026, 2, 28),
            chargesAmountCents: 9999,
          ),
        ];
        final total = sumChargeProvisionsForPeriod(
          payments: payments,
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        expect(total, 5000);
      },
    );
  });

  group('sumChargeProvisionsForPeriod — recouvrement aux bornes', () {
    test('paiement à cheval sur le début de période → inclus en totalité '
        '(pas de proratisation)', () {
      final payments = [
        _makePayment(
          periodStart: DateTime(2024, 12, 15),
          periodEnd: DateTime(2025, 1, 15),
          chargesAmountCents: 5000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('paiement à cheval sur la fin de période → inclus en totalité', () {
      final payments = [
        _makePayment(
          periodStart: DateTime(2025, 12, 15),
          periodEnd: DateTime(2026, 1, 15),
          chargesAmountCents: 5000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('paiement exactement égal à la période de référence → inclus', () {
      final payments = [
        _makePayment(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          chargesAmountCents: 12000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 12000);
    });

    test('periodEnd du paiement == referenceStart (1 jour de recouvrement) '
        '→ inclus', () {
      final payments = [
        _makePayment(
          periodStart: DateTime(2024, 12, 1),
          periodEnd: DateTime(2025, 1, 1),
          chargesAmountCents: 5000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('periodStart du paiement == referenceEnd + 1 jour → exclu (aucun '
        'recouvrement)', () {
      final payments = [
        _makePayment(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          chargesAmountCents: 5000,
        ),
      ];
      final total = sumChargeProvisionsForPeriod(
        payments: payments,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group('sumChargeProvisionsForPeriod — invariant round-trip UTC (régression '
      'fuseau horaire, même pattern que lease_lateness_test.dart)', () {
    // En chaîne de prod, `periodStart`/`periodEnd` d'un [Payment] relu
    // depuis Firestore sont écrits `.toUtc().toIso8601String()` puis
    // reparsés (`firestoreDocToSnakeJson`) — `DateTime.parse` sur cette
    // chaîne suffixée `Z` renvoie un `DateTime` UTC, pas local. Ce test
    // vérifie l'INVARIANT que la fonction doit respecter : le total
    // calculé ne doit PAS dépendre de la forme (locale vs
    // UTC-round-trippée) sous laquelle la même date civile est passée —
    // sinon deux appelants qui persistent/relisent la même donnée
    // obtiendraient des totaux incohérents selon le fuseau d'exécution du
    // runner. Reproduit exactement `roundTripUtc` de
    // `lease_lateness_test.dart` plutôt que de coder en dur un offset
    // Europe/Paris (fragile — dépendrait du fuseau de la machine CI).
    DateTime roundTripUtc(DateTime local) =>
        DateTime.parse(local.toUtc().toIso8601String());

    test('période de paiement UTC-round-trippée donne le MÊME total que la '
        'forme locale équivalente', () {
      final periodStartLocal = DateTime(2025, 1, 1);
      final periodEndLocal = DateTime(2025, 1, 31);

      final paymentLocal = _makePayment(
        periodStart: periodStartLocal,
        periodEnd: periodEndLocal,
        chargesAmountCents: 5000,
      );
      final paymentRoundTripped = _makePayment(
        periodStart: roundTripUtc(periodStartLocal),
        periodEnd: roundTripUtc(periodEndLocal),
        chargesAmountCents: 5000,
      );

      final totalLocal = sumChargeProvisionsForPeriod(
        payments: [paymentLocal],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      final totalRoundTripped = sumChargeProvisionsForPeriod(
        payments: [paymentRoundTripped],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );

      expect(totalRoundTripped, totalLocal);
      expect(totalRoundTripped, 5000);
    });

    test('référence de période UTC-round-trippée donne le MÊME total que la '
        'forme locale équivalente', () {
      final payment = _makePayment(
        periodStart: DateTime(2025, 6, 1),
        periodEnd: DateTime(2025, 6, 30),
        chargesAmountCents: 7500,
      );

      final totalLocal = sumChargeProvisionsForPeriod(
        payments: [payment],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      final totalRoundTripped = sumChargeProvisionsForPeriod(
        payments: [payment],
        referenceStart: roundTripUtc(DateTime(2025, 1, 1)),
        referenceEnd: roundTripUtc(DateTime(2025, 12, 31)),
      );

      expect(totalRoundTripped, totalLocal);
      expect(totalRoundTripped, 7500);
    });
  });
}
