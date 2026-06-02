/// Tests unitaires pour [ActivityItem].
library;

import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 6, 1);

  group('ActivityItem.paymentRecorded', () {
    test('construction et champs', () {
      final item = ActivityItem.paymentRecorded(
        paymentId: 'pay-1',
        leaseId: 'lease-1',
        tenantName: 'Jean Dupont',
        amountCents: 90000,
        occurredAt: now,
      );
      expect(
        item,
        isA<ActivityPaymentRecorded>()
            .having((p) => p.paymentId, 'paymentId', 'pay-1')
            .having((p) => p.leaseId, 'leaseId', 'lease-1')
            .having((p) => p.tenantName, 'tenantName', 'Jean Dupont')
            .having((p) => p.amountCents, 'amountCents', 90000),
      );
    });

    test('when — branche paymentRecorded atteinte', () {
      final item = ActivityItem.paymentRecorded(
        paymentId: 'p1',
        leaseId: 'l1',
        tenantName: 'Test',
        amountCents: 1000,
        occurredAt: now,
      );
      final result = item.when(
        paymentRecorded: (p0, p1, p2, p3, d) => 'payment',
        receiptGenerated: (p0, p1, p2, p3, d) => 'receipt',
        documentUploaded: (p0, p1, p2, p3, p4, d) => 'document',
      );
      expect(result, 'payment');
    });
  });

  group('ActivityItem.receiptGenerated', () {
    test('construction et champs', () {
      final item = ActivityItem.receiptGenerated(
        receiptId: 'rec-1',
        leaseId: 'lease-1',
        periodLabel: 'mai 2026',
        totalCents: 90000,
        occurredAt: now,
      );
      expect(
        item,
        isA<ActivityReceiptGenerated>()
            .having((r) => r.receiptId, 'receiptId', 'rec-1')
            .having((r) => r.periodLabel, 'periodLabel', 'mai 2026'),
      );
    });
  });

  group('ActivityItem.documentUploaded', () {
    test('construction et champs', () {
      final item = ActivityItem.documentUploaded(
        documentId: 'doc-1',
        leaseId: 'lease-1',
        categoryLabel: 'Bail signé',
        filename: 'bail.pdf',
        sizeBytes: 102400,
        occurredAt: now,
      );
      expect(
        item,
        isA<ActivityDocumentUploaded>()
            .having((d) => d.filename, 'filename', 'bail.pdf')
            .having((d) => d.sizeBytes, 'sizeBytes', 102400),
      );
    });
  });

  group('ActivityItem equality', () {
    test('mêmes valeurs → égaux', () {
      final a = ActivityItem.paymentRecorded(
        paymentId: 'p1',
        leaseId: 'l1',
        tenantName: 'Test',
        amountCents: 100,
        occurredAt: now,
      );
      final b = ActivityItem.paymentRecorded(
        paymentId: 'p1',
        leaseId: 'l1',
        tenantName: 'Test',
        amountCents: 100,
        occurredAt: now,
      );
      expect(a, equals(b));
    });
  });
}
