/// Tests unitaires de [receiptStatusPill] et helpers associés.
///
/// Couvre les 5 statuts effectifs + [receiptSecondaryLine].
library;

import 'package:easyrent/core/ui/cards/status_pill_tone.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/presentation/widgets/receipt_status_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  bool isVoided = false,
  bool isStale = false,
  List<String> paymentIds = const [],
  DateTime? sentAt,
  String? sentToEmail,
  DateTime? voidedAt,
  String? voidedReason,
}) => Receipt(
  id: 'r-1',
  landlordId: 'l-1',
  leaseId: 'lease-1',
  paymentIds: paymentIds,
  periodStart: DateTime(2026, 3, 1),
  periodEnd: DateTime(2026, 3, 31),
  totalCents: 120000,
  rentCents: 110000,
  chargesCents: 10000,
  documentType: DocumentType.quittance,
  pdfPath: 'l-1/r-1.pdf',
  isVoided: isVoided,
  voidedAt: voidedAt,
  voidedReason: voidedReason,
  isStale: isStale,
  generatedAt: DateTime(2026, 3, 4),
  createdAt: DateTime(2026, 3, 4),
  sentAt: sentAt,
  sentToEmail: sentToEmail,
);

// ---------------------------------------------------------------------------
// Tests receiptStatusPill
// ---------------------------------------------------------------------------

void main() {
  group('receiptStatusPill', () {
    test('isVoided → danger "Annulée"', () {
      final r = _makeReceipt(isVoided: true);
      final pill = receiptStatusPill(r);
      expect(pill.tone, StatusPillTone.danger);
      expect(pill.label, 'Annulée');
    });

    test('isStale (non voided) → warning "Périmée"', () {
      final r = _makeReceipt(isStale: true);
      final pill = receiptStatusPill(r);
      expect(pill.tone, StatusPillTone.warning);
      expect(pill.label, 'Périmée');
    });

    test('hasBeenShared (non voided, non stale) → success "Envoyée"', () {
      final r = _makeReceipt(
        paymentIds: ['pay-1'],
        sentAt: DateTime(2026, 3, 5),
        sentToEmail: 'test@example.com',
      );
      final pill = receiptStatusPill(r);
      expect(pill.tone, StatusPillTone.success);
      expect(pill.label, 'Envoyée');
    });

    test('paymentIds non vide, non partagée → info "Payée"', () {
      final r = _makeReceipt(paymentIds: ['pay-1']);
      final pill = receiptStatusPill(r);
      expect(pill.tone, StatusPillTone.info);
      expect(pill.label, 'Payée');
    });

    test('aucun paiement, non partagée → info "Émise"', () {
      final r = _makeReceipt();
      final pill = receiptStatusPill(r);
      expect(pill.tone, StatusPillTone.info);
      expect(pill.label, 'Émise');
    });

    test('isVoided prioritaire sur isStale → danger "Annulée"', () {
      final r = _makeReceipt(isVoided: true, isStale: true);
      final pill = receiptStatusPill(r);
      expect(pill.tone, StatusPillTone.danger);
      expect(pill.label, 'Annulée');
    });
  });

  // ---------------------------------------------------------------------------
  // Tests receiptSecondaryLine
  // ---------------------------------------------------------------------------

  group('receiptSecondaryLine', () {
    test('voided → "Annulée le DD/MM"', () {
      final r = _makeReceipt(isVoided: true, voidedAt: DateTime(2026, 3, 6));
      final line = receiptSecondaryLine(r);
      expect(line, contains('Annulée le 06/03'));
    });

    test('voided sans voidedAt → utilise generatedAt', () {
      final r = _makeReceipt(isVoided: true);
      final line = receiptSecondaryLine(r);
      expect(line, startsWith('Annulée le'));
    });

    test(
      'paid + sent → "Payée le DD/MM · Partagée le DD/MM à email masqué"',
      () {
        final r = _makeReceipt(
          paymentIds: ['pay-1'],
          sentAt: DateTime(2026, 3, 5),
          sentToEmail: 'marie@example.com',
        );
        final line = receiptSecondaryLine(r);
        expect(line, contains('Payée le'));
        expect(line, contains('Partagée le 05/03'));
        expect(line, contains('m***@example.com'));
      },
    );

    test('paid non partagée → "Payée le DD/MM"', () {
      final r = _makeReceipt(paymentIds: ['pay-1']);
      final line = receiptSecondaryLine(r);
      expect(line, startsWith('Payée le'));
      expect(line, isNot(contains('Partagée')));
    });

    test('émise (aucun paiement, non partagée) → "Émise le DD/MM"', () {
      final r = _makeReceipt();
      final line = receiptSecondaryLine(r);
      expect(line, startsWith('Émise le'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tests receiptPeriodMonthYear
  // ---------------------------------------------------------------------------

  group('receiptPeriodMonthYear', () {
    test('capitalise le premier caractère du mois', () {
      final r = _makeReceipt();
      final label = receiptPeriodMonthYear(r);
      // Mois de mars 2026.
      expect(label, 'Mars 2026');
    });
  });
}
