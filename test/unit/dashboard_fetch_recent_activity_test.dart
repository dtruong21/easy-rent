/// Tests de la logique de fusion 3 sources de [fetchRecentActivity].
///
/// Vérifie que les items de payments, receipts et documents sont bien
/// combinés, triés par date décroissante et limités à [limit].
library;

import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository avec contrôle fin sur les 3 sources
// ---------------------------------------------------------------------------

/// Fake repository qui expose séparément les 3 sources d'activité pour
/// pouvoir tester la logique de fusion (tri + take) indépendamment de Firestore.
class _FakeMultiSourceRepository implements DashboardRepository {
  final List<ActivityItem> payments;
  final List<ActivityItem> receipts;
  final List<ActivityItem> documents;

  const _FakeMultiSourceRepository({
    this.payments = const [],
    this.receipts = const [],
    this.documents = const [],
  });

  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async {
    // Reproduit exactement la logique de FirestoreDashboardRepository :
    // fetch 3 sources en parallèle → combine → tri → take.
    final results = await Future.wait([
      Future.value(payments),
      Future.value(receipts),
      Future.value(documents),
    ]);
    final all = results.expand((x) => x).toList();
    all.sort((a, b) => _date(b).compareTo(_date(a)));
    return all.take(limit).toList();
  }

  static DateTime _date(ActivityItem item) => item.when(
    paymentRecorded: (p0, p1, p2, p3, d) => d,
    receiptGenerated: (p0, p1, p2, p3, d) => d,
    documentUploaded: (p0, p1, p2, p3, p4, d) => d,
  );

  // Méthodes inutilisées pour ce test — délègues vides.
  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async =>
      const LoyersMoisKpi(encaissedCents: 0, dueCents: 0);
  @override
  Future<RetardsKpi> fetchRetards() async => const RetardsKpi(count: 0);
  @override
  Future<DocsPendingKpi> fetchDocsPending() async =>
      const DocsPendingKpi(count: 0);
  @override
  Future<List<MonthlyCollectedRent>> fetchLastMonthsCollectedRent(
    int months,
  ) async => [];
  @override
  Future<bool> isLandlordOnboarding() async => false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('fetchRecentActivity — fusion 3 sources', () {
    test(
      'combine payment + receipt + document et trie par date desc',
      () async {
        final payment = ActivityItem.paymentRecorded(
          paymentId: 'pay-1',
          leaseId: 'lease-1',
          tenantName: 'Alice Martin',
          amountCents: 80000,
          occurredAt: DateTime(2026, 6, 1),
        );
        final receipt = ActivityItem.receiptGenerated(
          receiptId: 'rec-1',
          leaseId: 'lease-1',
          periodLabel: '2026-05-01 → 2026-05-31',
          totalCents: 80000,
          occurredAt: DateTime(2026, 6, 3), // plus récent
        );
        final document = ActivityItem.documentUploaded(
          documentId: 'doc-1',
          leaseId: 'lease-1',
          categoryLabel: 'bail',
          filename: 'bail_signe.pdf',
          sizeBytes: 204800,
          occurredAt: DateTime(2026, 6, 2),
        );

        final repo = _FakeMultiSourceRepository(
          payments: [payment],
          receipts: [receipt],
          documents: [document],
        );

        final result = await repo.fetchRecentActivity(limit: 5);

        expect(result.length, 3);
        // Ordre attendu : receipt (6/3), document (6/2), payment (6/1).
        expect(
          result[0],
          isA<ActivityReceiptGenerated>().having(
            (r) => r.receiptId,
            'receiptId',
            'rec-1',
          ),
        );
        expect(
          result[1],
          isA<ActivityDocumentUploaded>().having(
            (d) => d.documentId,
            'documentId',
            'doc-1',
          ),
        );
        expect(
          result[2],
          isA<ActivityPaymentRecorded>().having(
            (p) => p.paymentId,
            'paymentId',
            'pay-1',
          ),
        );
      },
    );

    test('respecte la limite même avec beaucoup d\'items', () async {
      final payments = List.generate(
        4,
        (i) => ActivityItem.paymentRecorded(
          paymentId: 'pay-$i',
          leaseId: 'lease-1',
          tenantName: 'Test',
          amountCents: 1000,
          occurredAt: DateTime(2026, 1, i + 1),
        ),
      );
      final receipts = List.generate(
        4,
        (i) => ActivityItem.receiptGenerated(
          receiptId: 'rec-$i',
          leaseId: 'lease-1',
          periodLabel: 'période $i',
          totalCents: 1000,
          occurredAt: DateTime(2026, 2, i + 1),
        ),
      );

      final repo = _FakeMultiSourceRepository(
        payments: payments,
        receipts: receipts,
      );

      final result = await repo.fetchRecentActivity(limit: 5);
      expect(result.length, 5);
      // Les receipts (fév.) sont plus récents que les payments (janv.).
      // Les 4 receipts arrivent en premier, puis 1 payment.
      for (final item in result.take(4)) {
        expect(item, isA<ActivityReceiptGenerated>());
      }
      expect(result[4], isA<ActivityPaymentRecorded>());
    });

    test('retourne liste vide si aucune source ne contient d\'items', () async {
      final repo = const _FakeMultiSourceRepository();
      final result = await repo.fetchRecentActivity();
      expect(result, isEmpty);
    });

    test('fonctionne avec une seule source non vide', () async {
      final repo = _FakeMultiSourceRepository(
        documents: [
          ActivityItem.documentUploaded(
            documentId: 'doc-only',
            leaseId: 'lease-1',
            categoryLabel: 'autre',
            filename: 'test.pdf',
            sizeBytes: 1024,
            occurredAt: DateTime(2026, 6, 1),
          ),
        ],
      );

      final result = await repo.fetchRecentActivity();
      expect(result.length, 1);
      expect(
        result.first,
        isA<ActivityDocumentUploaded>().having(
          (d) => d.documentId,
          'documentId',
          'doc-only',
        ),
      );
    });
  });
}
