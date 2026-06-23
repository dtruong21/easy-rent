/// Tests de sérialisation JSON du champ [reference] sur [Payment].
///
/// Couvre : round-trip avec reference renseignée, round-trip sans reference
/// (backward compat), clé JSON = 'reference'.
library;

import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Payment _makePayment({String? reference, String? notes}) => Payment(
  id: 'pay-ref-001',
  leaseId: 'lease-001',
  landlordId: 'landlord-001',
  periodStart: DateTime(2024, 1, 1),
  periodEnd: DateTime(2024, 1, 31),
  paidAt: DateTime(2024, 1, 5),
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  paymentMethod: PaymentMethod.virement,
  notes: notes,
  reference: reference,
  createdAt: DateTime(2024, 1, 1, 10, 0),
  updatedAt: DateTime(2024, 1, 1, 10, 0),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('Payment.reference — round-trip avec reference renseignée', () {
    test('reference non null → préservée après round-trip', () {
      final p = _makePayment(reference: 'VIR-2024-001');
      final rt = Payment.fromJson(p.toJson());
      expect(rt.reference, 'VIR-2024-001');
    });

    test('reference avec espaces → préservée telle quelle en JSON', () {
      final p = _makePayment(reference: 'CHQ 1234');
      final rt = Payment.fromJson(p.toJson());
      expect(rt.reference, 'CHQ 1234');
    });

    test('reference 100 caractères (limite max) → round-trip correct', () {
      final maxRef = 'A' * 100;
      final p = _makePayment(reference: maxRef);
      final rt = Payment.fromJson(p.toJson());
      expect(rt.reference, maxRef);
    });
  });

  // -------------------------------------------------------------------------
  group('Payment.reference — backward compat (reference null)', () {
    test('reference = null → préservée null après round-trip', () {
      final p = _makePayment();
      final rt = Payment.fromJson(p.toJson());
      expect(rt.reference, isNull);
    });

    test(
      'JSON sans clé reference → Payment.fromJson retourne reference null',
      () {
        final json = _makePayment().toJson()..remove('reference');
        final p = Payment.fromJson(json);
        expect(p.reference, isNull);
      },
    );

    test(
      'JSON avec reference = null explicite → Payment.fromJson retourne null',
      () {
        final json = _makePayment().toJson()..[' reference'] = null;
        final p = Payment.fromJson(json);
        expect(p.reference, isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('Payment.reference — clé JSON', () {
    test('toJson contient la clé "reference" si non null', () {
      final p = _makePayment(reference: 'REF-001');
      final json = p.toJson();
      expect(json.containsKey('reference'), isTrue);
      expect(json['reference'], 'REF-001');
    });

    test(
      'toJson contient la clé "reference" avec null si reference est null',
      () {
        final p = _makePayment();
        final json = p.toJson();
        // freezed sérialise les nullable comme null (clé présente avec valeur null)
        expect(json['reference'], isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('Payment.reference — indépendant du champ notes', () {
    test('reference et notes peuvent être non null simultanément', () {
      final p = _makePayment(reference: 'VIR-001', notes: 'Paiement partiel');
      final rt = Payment.fromJson(p.toJson());
      expect(rt.reference, 'VIR-001');
      expect(rt.notes, 'Paiement partiel');
    });

    test('reference non null, notes null → les deux préservés', () {
      final p = _makePayment(reference: 'VIR-002');
      final rt = Payment.fromJson(p.toJson());
      expect(rt.reference, 'VIR-002');
      expect(rt.notes, isNull);
    });

    test('reference null, notes non null → les deux préservés', () {
      final p = _makePayment(notes: 'Note seule');
      final rt = Payment.fromJson(p.toJson());
      expect(rt.reference, isNull);
      expect(rt.notes, 'Note seule');
    });
  });
}
