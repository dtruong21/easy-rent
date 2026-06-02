/// Tests du contrat [DashboardRepository] via un fake in-memory.
///
/// NOTE : [SupabaseDashboardRepository] utilise [Db.from()] qui dépend de
/// [Supabase.instance.client] — non initialisé en test unitaire.
/// On teste donc le contrat de l'interface + les invariants du fake.
library;

import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/monthly_amount.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake in-memory repository
// ---------------------------------------------------------------------------

class _FakeDashboardRepository implements DashboardRepository {
  final LoyersMoisKpi _loyers;
  final RetardsKpi _retards;
  final RenouvellementsKpi _renouvellements;
  final DocsPendingKpi _docs;
  final List<MonthlyAmount> _monthly;
  final List<ActivityItem> _activity;
  final bool _onboarding;

  const _FakeDashboardRepository({
    LoyersMoisKpi? loyers,
    RetardsKpi? retards,
    RenouvellementsKpi? renouvellements,
    DocsPendingKpi? docs,
    List<MonthlyAmount>? monthly,
    List<ActivityItem>? activity,
    bool onboarding = false,
  }) : _loyers =
           loyers ??
           const LoyersMoisKpi(encaissedCents: 85000, dueCents: 90000),
       _retards = retards ?? const RetardsKpi(count: 0),
       _renouvellements = renouvellements ?? const RenouvellementsKpi(count: 0),
       _docs = docs ?? const DocsPendingKpi(count: 0),
       _monthly = monthly ?? const [],
       _activity = activity ?? const [],
       _onboarding = onboarding;

  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async => _loyers;

  @override
  Future<RetardsKpi> fetchRetards() async => _retards;

  @override
  Future<RenouvellementsKpi> fetchRenouvellements() async => _renouvellements;

  @override
  Future<DocsPendingKpi> fetchDocsPending() async => _docs;

  @override
  Future<List<MonthlyAmount>> fetchLast6MonthsAmounts() async => _monthly;

  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async =>
      _activity.take(limit).toList();

  @override
  Future<bool> isLandlordOnboarding() async => _onboarding;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('fetchLoyersMois', () {
    test('retourne les loyers configurés', () async {
      final repo = _FakeDashboardRepository(
        loyers: const LoyersMoisKpi(encaissedCents: 100000, dueCents: 100000),
      );
      final kpi = await repo.fetchLoyersMois();
      expect(kpi.encaissedCents, 100000);
      expect(kpi.dueCents, 100000);
    });

    test('défaut : encaissedCents=85000, dueCents=90000', () async {
      final repo = const _FakeDashboardRepository();
      final kpi = await repo.fetchLoyersMois();
      expect(kpi.encaissedCents, 85000);
      expect(kpi.dueCents, 90000);
    });
  });

  group('fetchRetards', () {
    test('retourne count=0 par défaut', () async {
      final repo = const _FakeDashboardRepository();
      final kpi = await repo.fetchRetards();
      expect(kpi.count, 0);
    });

    test('retourne count configuré', () async {
      final repo = _FakeDashboardRepository(
        retards: const RetardsKpi(count: 3),
      );
      final kpi = await repo.fetchRetards();
      expect(kpi.count, 3);
    });
  });

  group('fetchRenouvellements', () {
    test('retourne count=0 par défaut', () async {
      final repo = const _FakeDashboardRepository();
      final kpi = await repo.fetchRenouvellements();
      expect(kpi.count, 0);
    });

    test('retourne count configuré', () async {
      final repo = _FakeDashboardRepository(
        renouvellements: const RenouvellementsKpi(count: 2),
      );
      final kpi = await repo.fetchRenouvellements();
      expect(kpi.count, 2);
    });
  });

  group('fetchDocsPending', () {
    test('retourne count=0 par défaut', () async {
      final repo = const _FakeDashboardRepository();
      final kpi = await repo.fetchDocsPending();
      expect(kpi.count, 0);
    });
  });

  group('fetchLast6MonthsAmounts', () {
    test('retourne liste vide par défaut', () async {
      final repo = const _FakeDashboardRepository();
      final months = await repo.fetchLast6MonthsAmounts();
      expect(months, isEmpty);
    });

    test('retourne 6 mois configurés', () async {
      final sixMonths = List.generate(
        6,
        (i) => MonthlyAmount(
          year: 2026,
          month: i + 1,
          encaissedCents: (i + 1) * 10000,
          dueCents: 90000,
        ),
      );
      final repo = _FakeDashboardRepository(monthly: sixMonths);
      final months = await repo.fetchLast6MonthsAmounts();
      expect(months.length, 6);
      expect(months.first.month, 1);
    });
  });

  group('fetchRecentActivity', () {
    test('retourne liste vide par défaut', () async {
      final repo = const _FakeDashboardRepository();
      final activity = await repo.fetchRecentActivity();
      expect(activity, isEmpty);
    });

    test('respecte la limite', () async {
      final items = List.generate(
        10,
        (i) => ActivityItem.paymentRecorded(
          paymentId: 'pay-$i',
          leaseId: 'lease-1',
          tenantName: 'Test',
          amountCents: 1000,
          occurredAt: DateTime(2026, 6, i + 1),
        ),
      );
      final repo = _FakeDashboardRepository(activity: items);
      final result = await repo.fetchRecentActivity(limit: 5);
      expect(result.length, 5);
    });
  });

  group('isLandlordOnboarding', () {
    test('retourne false par défaut', () async {
      final repo = const _FakeDashboardRepository();
      expect(await repo.isLandlordOnboarding(), isFalse);
    });

    test('retourne true si configuré', () async {
      final repo = const _FakeDashboardRepository(onboarding: true);
      expect(await repo.isLandlordOnboarding(), isTrue);
    });
  });
}
