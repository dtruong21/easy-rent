import 'package:easyrent/features/receipts/application/receipts_filter_provider.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_status_filter.dart';
import 'package:flutter_test/flutter_test.dart';

Receipt _makeReceipt({
  required String id,
  required DateTime periodStart,
  bool isVoided = false,
  List<String> paymentIds = const [],
  DateTime? sentAt,
}) => Receipt(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: paymentIds,
  periodStart: periodStart,
  periodEnd: periodStart.add(const Duration(days: 30)),
  totalCents: 120000,
  rentCents: 110000,
  chargesCents: 10000,
  documentType: DocumentType.quittance,
  pdfPath: 'l-1/$id.pdf',
  isVoided: isVoided,
  voidedAt: isVoided ? periodStart.add(const Duration(days: 10)) : null,
  isStale: false,
  generatedAt: periodStart.add(const Duration(days: 5)),
  createdAt: periodStart.add(const Duration(days: 5)),
  sentAt: sentAt,
  sentToEmail: sentAt != null ? 'tenant@example.com' : null,
);

void main() {
  // Partagée (hasBeenShared == true), non annulée, non payée.
  final partagee = _makeReceipt(
    id: 'r-shared',
    periodStart: DateTime(2026, 3, 1),
    sentAt: DateTime(2026, 3, 6),
  );

  // Payée, non partagée, non annulée.
  final payeeNonPartagee = _makeReceipt(
    id: 'r-paid',
    periodStart: DateTime(2026, 4, 1),
    paymentIds: const ['pay-1'],
  );

  // Annulée.
  final annulee = _makeReceipt(
    id: 'r-voided',
    periodStart: DateTime(2026, 5, 1),
    isVoided: true,
  );

  // Année précédente — émise, ni payée ni partagée ni annulée.
  final anneePrecedente = _makeReceipt(
    id: 'r-2025',
    periodStart: DateTime(2025, 6, 1),
  );

  final receipts = [partagee, payeeNonPartagee, annulee, anneePrecedente];

  group('receiptMatchesStatus', () {
    test('all — toujours vrai', () {
      for (final r in receipts) {
        expect(receiptMatchesStatus(r, ReceiptStatusFilter.all), isTrue);
      }
    });

    test('sent — hasBeenShared && !isVoided', () {
      expect(receiptMatchesStatus(partagee, ReceiptStatusFilter.sent), isTrue);
      expect(
        receiptMatchesStatus(payeeNonPartagee, ReceiptStatusFilter.sent),
        isFalse,
      );
      expect(receiptMatchesStatus(annulee, ReceiptStatusFilter.sent), isFalse);
      expect(
        receiptMatchesStatus(anneePrecedente, ReceiptStatusFilter.sent),
        isFalse,
      );
    });

    test('paid — paymentIds non vide && !isVoided', () {
      expect(
        receiptMatchesStatus(payeeNonPartagee, ReceiptStatusFilter.paid),
        isTrue,
      );
      expect(receiptMatchesStatus(partagee, ReceiptStatusFilter.paid), isFalse);
      expect(receiptMatchesStatus(annulee, ReceiptStatusFilter.paid), isFalse);
      expect(
        receiptMatchesStatus(anneePrecedente, ReceiptStatusFilter.paid),
        isFalse,
      );
    });

    test('voided — isVoided', () {
      expect(receiptMatchesStatus(annulee, ReceiptStatusFilter.voided), isTrue);
      expect(
        receiptMatchesStatus(partagee, ReceiptStatusFilter.voided),
        isFalse,
      );
      expect(
        receiptMatchesStatus(payeeNonPartagee, ReceiptStatusFilter.voided),
        isFalse,
      );
      expect(
        receiptMatchesStatus(anneePrecedente, ReceiptStatusFilter.voided),
        isFalse,
      );
    });
  });

  group('receiptStatusCounts', () {
    test('year fourni — ignore l\'année précédente', () {
      final counts = receiptStatusCounts(receipts, 2026);
      expect(counts, {
        ReceiptStatusFilter.all: 3,
        ReceiptStatusFilter.sent: 1,
        ReceiptStatusFilter.paid: 1,
        ReceiptStatusFilter.voided: 1,
      });
    });

    test('year == null — compte toutes les années', () {
      final counts = receiptStatusCounts(receipts, null);
      expect(counts, {
        ReceiptStatusFilter.all: 4,
        ReceiptStatusFilter.sent: 1,
        ReceiptStatusFilter.paid: 1,
        ReceiptStatusFilter.voided: 1,
      });
    });
  });
}
