/// Tests unitaires du modèle [Payment] — round-trip JSON.
///
/// Couvre : toutes les valeurs de [PaymentMethod], dates YYYY-MM-DD,
/// notes null et non null, deleted_at null et non null.
library;

import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Payment _makePayment({
  String id = 'pay-001',
  String leaseId = 'lease-001',
  String landlordId = 'landlord-001',
  DateTime? periodStart,
  DateTime? periodEnd,
  DateTime? paidAt,
  int rentAmountCents = 85000,
  int chargesAmountCents = 5000,
  PaymentMethod paymentMethod = PaymentMethod.virement,
  String? notes,
  DateTime? deletedAt,
}) {
  return Payment(
    id: id,
    leaseId: leaseId,
    landlordId: landlordId,
    periodStart: periodStart ?? DateTime(2024, 1, 1),
    periodEnd: periodEnd ?? DateTime(2024, 1, 31),
    paidAt: paidAt ?? DateTime(2024, 1, 5),
    rentAmountCents: rentAmountCents,
    chargesAmountCents: chargesAmountCents,
    paymentMethod: paymentMethod,
    notes: notes,
    createdAt: DateTime(2024, 1, 1, 10, 0),
    updatedAt: DateTime(2024, 1, 1, 10, 0),
    deletedAt: deletedAt,
  );
}

/// Vérifie l'égalité champ par champ (sans deletedAt dans les noms).
void _expectEqual(Payment a, Payment b) {
  expect(a.id, b.id, reason: 'id');
  expect(a.leaseId, b.leaseId, reason: 'leaseId');
  expect(a.landlordId, b.landlordId, reason: 'landlordId');
  expect(a.periodStart, b.periodStart, reason: 'periodStart');
  expect(a.periodEnd, b.periodEnd, reason: 'periodEnd');
  expect(a.paidAt, b.paidAt, reason: 'paidAt');
  expect(a.rentAmountCents, b.rentAmountCents, reason: 'rentAmountCents');
  expect(
    a.chargesAmountCents,
    b.chargesAmountCents,
    reason: 'chargesAmountCents',
  );
  expect(a.paymentMethod, b.paymentMethod, reason: 'paymentMethod');
  expect(a.notes, b.notes, reason: 'notes');
  expect(a.deletedAt, b.deletedAt, reason: 'deletedAt');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('Payment.fromJson(p.toJson()) — round-trip basique', () {
    test('payment standard → identique après round-trip', () {
      final p = _makePayment();
      _expectEqual(p, Payment.fromJson(p.toJson()));
    });
  });

  // -------------------------------------------------------------------------
  group('Payment — round-trip pour tous les PaymentMethod', () {
    for (final method in PaymentMethod.values) {
      test('paymentMethod ${method.name} → round-trip cohérent', () {
        final p = _makePayment(paymentMethod: method);
        final roundTripped = Payment.fromJson(p.toJson());
        expect(roundTripped.paymentMethod, method);
      });
    }
  });

  // -------------------------------------------------------------------------
  group('Payment — sérialisation dates YYYY-MM-DD', () {
    test('period_start sérialisé en YYYY-MM-DD', () {
      final p = _makePayment(periodStart: DateTime(2024, 3, 15));
      final json = p.toJson();
      expect(json['period_start'], '2024-03-15');
    });

    test('period_end sérialisé en YYYY-MM-DD', () {
      final p = _makePayment(periodEnd: DateTime(2024, 3, 31));
      final json = p.toJson();
      expect(json['period_end'], '2024-03-31');
    });

    test('paid_at sérialisé en YYYY-MM-DD', () {
      final p = _makePayment(paidAt: DateTime(2024, 3, 5));
      final json = p.toJson();
      expect(json['paid_at'], '2024-03-05');
    });

    test('période en début d\'année (01-01) → round-trip correct', () {
      final p = _makePayment(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 1, 31),
        paidAt: DateTime(2025, 1, 3),
      );
      final rt = Payment.fromJson(p.toJson());
      expect(rt.periodStart, DateTime(2025, 1, 1));
      expect(rt.periodEnd, DateTime(2025, 1, 31));
      expect(rt.paidAt, DateTime(2025, 1, 3));
    });
  });

  // -------------------------------------------------------------------------
  group('Payment — notes null et non null', () {
    test('notes = null → round-trip préserve null', () {
      final p = _makePayment(notes: null);
      final rt = Payment.fromJson(p.toJson());
      expect(rt.notes, isNull);
    });

    test('notes non null → round-trip préserve la valeur', () {
      final p = _makePayment(notes: 'Paiement en deux fois');
      final rt = Payment.fromJson(p.toJson());
      expect(rt.notes, 'Paiement en deux fois');
    });

    test('notes chaîne vide → round-trip préserve la chaîne vide', () {
      final p = _makePayment(notes: '');
      final rt = Payment.fromJson(p.toJson());
      expect(rt.notes, '');
    });
  });

  // -------------------------------------------------------------------------
  group('Payment — deleted_at null et non null', () {
    test('deleted_at = null → round-trip préserve null', () {
      final p = _makePayment(deletedAt: null);
      final rt = Payment.fromJson(p.toJson());
      expect(rt.deletedAt, isNull);
    });

    test('deleted_at non null → round-trip préserve la valeur', () {
      final deletedAt = DateTime(2024, 6, 15, 14, 30);
      final p = _makePayment(deletedAt: deletedAt);
      final rt = Payment.fromJson(p.toJson());
      expect(rt.deletedAt, isNotNull);
      // La comparaison porte sur la précision milliseconde (ISO 8601).
      expect(
        rt.deletedAt!.millisecondsSinceEpoch,
        deletedAt.millisecondsSinceEpoch,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Payment — totalAmountCents extension', () {
    test('totalAmountCents = rentAmountCents + chargesAmountCents', () {
      final p = _makePayment(rentAmountCents: 85000, chargesAmountCents: 5000);
      expect(p.totalAmountCents, 90000);
    });

    test('totalAmountCents avec charges = 0', () {
      final p = _makePayment(rentAmountCents: 70000, chargesAmountCents: 0);
      expect(p.totalAmountCents, 70000);
    });
  });

  // -------------------------------------------------------------------------
  group('Payment — JSON keys snake_case', () {
    test('toJson contient les bonnes clés snake_case', () {
      final p = _makePayment();
      final json = p.toJson();
      expect(json.containsKey('lease_id'), isTrue);
      expect(json.containsKey('landlord_id'), isTrue);
      expect(json.containsKey('period_start'), isTrue);
      expect(json.containsKey('period_end'), isTrue);
      expect(json.containsKey('paid_at'), isTrue);
      expect(json.containsKey('rent_amount_cents'), isTrue);
      expect(json.containsKey('charges_amount_cents'), isTrue);
      expect(json.containsKey('payment_method'), isTrue);
    });

    test('payment_method sérialisé en snake_case SQL', () {
      expect(
        _makePayment(
          paymentMethod: PaymentMethod.prelevement,
        ).toJson()['payment_method'],
        'prelevement',
      );
      expect(
        _makePayment(
          paymentMethod: PaymentMethod.cheque,
        ).toJson()['payment_method'],
        'cheque',
      );
    });
  });
}
