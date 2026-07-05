/// Tests de [SharePayloadBuilder].
///
/// Couvre :
/// - sujet au format "Quittance de loyer — [mois] [année]"
/// - body contient le prénom, la période, l'adresse, le bailleur
/// - filename slug correct (accents, espaces → underscores)
library;

import 'package:easyrent/features/receipts/data/share_payload_builder.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Receipt _makeReceipt({DateTime? periodStart, DateTime? periodEnd}) {
  return Receipt(
    id: 'r-1',
    landlordId: 'landlord-1',
    leaseId: 'lease-1',
    paymentIds: ['pay-1'],
    periodStart: periodStart ?? DateTime(2026, 3, 1),
    periodEnd: periodEnd ?? DateTime(2026, 3, 31),
    totalCents: 90000,
    rentCents: 85000,
    chargesCents: 5000,
    documentType: DocumentType.quittance,
    pdfPath: 'landlord-1/r-1.pdf',
    isVoided: false,
    isStale: false,
    generatedAt: DateTime(2026, 4, 1),
    createdAt: DateTime(2026, 4, 1),
  );
}

SharePayload _build({
  Receipt? receipt,
  String tenantFirstName = 'Jean',
  String propertyAddress = '12 rue de la Paix, 75001 Paris',
  String landlordFullName = 'Marie Martin',
}) {
  return SharePayloadBuilder.build(
    receipt: receipt ?? _makeReceipt(),
    tenantFirstName: tenantFirstName,
    propertyAddress: propertyAddress,
    landlordFullName: landlordFullName,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SharePayloadBuilder.build — sujet', () {
    test('format "Quittance de loyer — <mois> <année>"', () {
      final payload = _build();
      expect(payload.subject, 'Quittance de loyer — mars 2026');
    });

    test('mois avec accent (août)', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 8, 1),
          periodEnd: DateTime(2026, 8, 31),
        ),
      );
      expect(payload.subject, 'Quittance de loyer — août 2026');
    });

    test('mois sans accent (janvier)', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
        ),
      );
      expect(payload.subject, 'Quittance de loyer — janvier 2026');
    });

    test('mois de décembre', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 12, 1),
          periodEnd: DateTime(2026, 12, 31),
        ),
      );
      expect(payload.subject, 'Quittance de loyer — décembre 2026');
    });
  });

  group('SharePayloadBuilder.build — body', () {
    test('contient le prénom du locataire', () {
      final payload = _build(tenantFirstName: 'Pierre');
      expect(payload.body, contains('Pierre'));
    });

    test('commence par "Bonjour <prénom>"', () {
      final payload = _build(tenantFirstName: 'Sophie');
      expect(payload.body, startsWith('Bonjour Sophie,'));
    });

    test('contient la date de début de période', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 3, 1),
          periodEnd: DateTime(2026, 3, 31),
        ),
      );
      expect(payload.body, contains('01/03/2026'));
    });

    test('contient la date de fin de période', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 3, 1),
          periodEnd: DateTime(2026, 3, 31),
        ),
      );
      expect(payload.body, contains('31/03/2026'));
    });

    test('contient l\'adresse du logement', () {
      final payload = _build(
        propertyAddress: '5 avenue Victor Hugo, 69001 Lyon',
      );
      expect(payload.body, contains('5 avenue Victor Hugo, 69001 Lyon'));
    });

    test('contient le nom du bailleur', () {
      final payload = _build(landlordFullName: 'Dupont François');
      expect(payload.body, contains('Dupont François'));
    });

    test('contient la signature Baillan.', () {
      final payload = _build();
      expect(payload.body, contains('Baillan.'));
    });

    test('contient la mention "ci-joint"', () {
      final payload = _build();
      expect(payload.body, contains('ci-joint'));
    });
  });

  group('SharePayloadBuilder.build — filename', () {
    test('format "quittance_<mois>_<année>.pdf"', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 3, 1),
          periodEnd: DateTime(2026, 3, 31),
        ),
      );
      expect(payload.filename, 'quittance_mars_2026.pdf');
    });

    test('accents supprimés dans le filename (août → aout)', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 8, 1),
          periodEnd: DateTime(2026, 8, 31),
        ),
      );
      expect(payload.filename, 'quittance_aout_2026.pdf');
    });

    test('accents dans février → fevrier', () {
      final payload = _build(
        receipt: _makeReceipt(
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 2, 28),
        ),
      );
      expect(payload.filename, 'quittance_fevrier_2026.pdf');
    });

    test('filename sans espace ni caractère spécial', () {
      final payload = _build();
      expect(payload.filename, matches(RegExp(r'^[a-z0-9_\.]+$')));
    });
  });
}
