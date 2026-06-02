/// Tests du modèle [Receipt] — freezed, JSON round-trip, extensions.
library;

import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  String id = 'receipt-1',
  bool isVoided = false,
  bool isStale = false,
  DocumentType documentType = DocumentType.quittance,
  int totalCents = 90000,
  int rentCents = 85000,
  int chargesCents = 5000,
}) => Receipt(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: ['pay-1'],
  periodStart: DateTime(2026, 1, 1),
  periodEnd: DateTime(2026, 1, 31),
  totalCents: totalCents,
  rentCents: rentCents,
  chargesCents: chargesCents,
  documentType: documentType,
  pdfPath: 'landlord-1/receipt-1.pdf',
  isVoided: isVoided,
  isStale: isStale,
  generatedAt: DateTime(2026, 2, 1),
  createdAt: DateTime(2026, 2, 1),
);

Map<String, dynamic> _makeJson({
  String id = 'receipt-1',
  bool isVoided = false,
  bool isStale = false,
  String documentType = 'quittance',
}) => {
  'id': id,
  'landlord_id': 'landlord-1',
  'lease_id': 'lease-1',
  'payment_ids': ['pay-1'],
  'period_start': '2026-01-01',
  'period_end': '2026-01-31',
  'total_cents': 90000,
  'rent_cents': 85000,
  'charges_cents': 5000,
  'document_type': documentType,
  'pdf_path': 'landlord-1/receipt-1.pdf',
  'is_voided': isVoided,
  'voided_at': null,
  'voided_reason': null,
  'is_stale': isStale,
  'generated_at': '2026-02-01T00:00:00.000Z',
  'created_at': '2026-02-01T00:00:00.000Z',
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Receipt.fromJson', () {
    test('désérialise correctement un JSON valide', () {
      final json = _makeJson();
      final receipt = Receipt.fromJson(json);

      expect(receipt.id, 'receipt-1');
      expect(receipt.landlordId, 'landlord-1');
      expect(receipt.leaseId, 'lease-1');
      expect(receipt.paymentIds, ['pay-1']);
      expect(receipt.periodStart, DateTime(2026, 1, 1));
      expect(receipt.periodEnd, DateTime(2026, 1, 31));
      expect(receipt.totalCents, 90000);
      expect(receipt.rentCents, 85000);
      expect(receipt.chargesCents, 5000);
      expect(receipt.documentType, DocumentType.quittance);
      expect(receipt.pdfPath, 'landlord-1/receipt-1.pdf');
      expect(receipt.isVoided, false);
      expect(receipt.isStale, false);
      expect(receipt.voidedAt, isNull);
      expect(receipt.voidedReason, isNull);
    });

    test('désérialise document_type "recu"', () {
      final receipt = Receipt.fromJson(_makeJson(documentType: 'recu'));
      expect(receipt.documentType, DocumentType.recu);
    });

    test('désérialise is_voided = true', () {
      final receipt = Receipt.fromJson(_makeJson(isVoided: true));
      expect(receipt.isVoided, true);
    });

    test('désérialise is_stale = true', () {
      final receipt = Receipt.fromJson(_makeJson(isStale: true));
      expect(receipt.isStale, true);
    });
  });

  group('Receipt.toJson', () {
    test('sérialise correctement en JSON', () {
      final receipt = _makeReceipt();
      final json = receipt.toJson();

      expect(json['id'], 'receipt-1');
      expect(json['landlord_id'], 'landlord-1');
      expect(json['lease_id'], 'lease-1');
      expect(json['payment_ids'], ['pay-1']);
      expect(json['period_start'], '2026-01-01');
      expect(json['period_end'], '2026-01-31');
      expect(json['total_cents'], 90000);
      expect(json['document_type'], 'quittance');
      expect(json['is_voided'], false);
      expect(json['is_stale'], false);
    });
  });

  group('Receipt JSON round-trip', () {
    test('fromJson → toJson → fromJson est idempotent', () {
      final original = _makeReceipt();
      final json = original.toJson();
      final restored = Receipt.fromJson(json);
      expect(restored, original);
    });

    test('round-trip avec documentType recu', () {
      final original = _makeReceipt(documentType: DocumentType.recu);
      final restored = Receipt.fromJson(original.toJson());
      expect(restored.documentType, DocumentType.recu);
    });
  });

  group('ReceiptExtension', () {
    test('totalEuros formate correctement 90000 centimes', () {
      final receipt = _makeReceipt(totalCents: 90000);
      expect(receipt.totalEuros, contains('900'));
      expect(receipt.totalEuros, contains('€'));
    });

    test('periodLabel contient les deux dates formatées', () {
      final receipt = _makeReceipt();
      // periodLabel = "01/01/2026 – 31/01/2026"
      expect(receipt.periodLabel, contains('01/01/2026'));
      expect(receipt.periodLabel, contains('31/01/2026'));
    });
  });

  group('Receipt.copyWith', () {
    test('copyWith modifie un champ', () {
      final r = _makeReceipt();
      final voided = r.copyWith(isVoided: true);
      expect(voided.isVoided, true);
      expect(voided.id, r.id); // autres champs inchangés
    });
  });
}
