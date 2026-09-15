import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../../leases/domain/lease.dart';
import '../../leases/domain/lease_lateness.dart';
import '../../payments/domain/payment.dart';
import '../domain/activity_item.dart';
import '../domain/dashboard_kpi.dart';
import '../domain/onboarding_progress.dart';

final _log = Logger('DashboardRepository');

/// Repository dashboard — toutes les méthodes sont des SELECT (lecture seule).
///
/// Le filtre d'ownership `landlordId == auth.uid` doit être passé
/// explicitement dans chaque `where()` : les Firestore Rules l'exigent (elles
/// ne sont pas un filtre), donc sans ce `where()` côté client la query throw.
abstract interface class DashboardRepository {
  Future<LoyersMoisKpi> fetchLoyersMois();
  Future<RetardsKpi> fetchRetards();
  Future<DocsPendingKpi> fetchDocsPending();

  /// Loyers encaissés mois par mois sur les [months] derniers mois
  /// (fenêtre glissante : mois courant inclus, donc `now-(months-1) → now`).
  ///
  /// Alimente le graphique « Cash-flow mensuel » du dashboard
  /// (`monthlyCashflowProvider`, dashboard_provider.dart) — les dépenses non
  /// récupérables du même intervalle sont chargées séparément via
  /// `ExpensesRepository` puis combinées côté application (voir doc de tête
  /// de `MonthlyCollectedRent`).
  Future<List<MonthlyCollectedRent>> fetchLastMonthsCollectedRent(int months);
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5});
  Future<bool> isLandlordOnboarding();

  /// Progression d'onboarding dérivée (5 signaux + id d'un bail). Lecture seule.
  Future<OnboardingProgress> fetchOnboardingProgress();
}

class FirestoreDashboardRepository implements DashboardRepository {
  FirestoreDashboardRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — dashboard requires auth');
    }
    return uid;
  }

  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async {
    final uid = _uid;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final (paymentsQs, leasesQs) = await (
      _firestore
          .collection('payments')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .where(
            'paidAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart),
          )
          .where('paidAt', isLessThan: Timestamp.fromDate(monthEnd))
          .get(),
      _firestore
          .collection('leases')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .where('status', isEqualTo: 'active')
          .get(),
    ).wait;

    int encaissed = 0;
    for (final d in paymentsQs.docs) {
      final rent = (d.data()['rentAmountCents'] as num?)?.toInt() ?? 0;
      final charges = (d.data()['chargesAmountCents'] as num?)?.toInt() ?? 0;
      encaissed += rent + charges;
    }
    int due = 0;
    for (final d in leasesQs.docs) {
      final rent = (d.data()['rentAmountCents'] as num?)?.toInt() ?? 0;
      final charges = (d.data()['chargesAmountCents'] as num?)?.toInt() ?? 0;
      due += rent + charges;
    }
    _log.fine('fetchLoyersMois: encaissed=$encaissed due=$due');
    return LoyersMoisKpi(encaissedCents: encaissed, dueCents: due);
  }

  @override
  Future<RetardsKpi> fetchRetards() async {
    final uid = _uid;
    final now = DateTime.now();

    // FEAT-028 : PAS de filtre `startDate <= now-35j` ici — c'était le bug
    // qui rendait invisibles les baux récents dont la 1ʳᵉ échéance est déjà
    // dépassée (cas le plus urgent : nouveau locataire, premier test de
    // paiement). On charge TOUS les baux actifs, quelle que soit leur
    // ancienneté, et on délègue la détection de retard à `isLeaseLate()`
    // (couverture de période + délai de grâce de 5 jours, cf.
    // lease_lateness.dart).
    final leasesQs = await _firestore
        .collection('leases')
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .where('status', isEqualTo: 'active')
        .get();

    if (leasesQs.docs.isEmpty) return const RetardsKpi(count: 0);

    final leases = leasesQs.docs
        .map(
          (d) => Lease.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();
    final leaseIds = leases.map((l) => l.id).toList();

    // Charge TOUT l'historique de paiements par bail (pas juste le
    // dernier) — nécessaire pour tester le recouvrement de période, pas
    // seulement la date du dernier paiement enregistré. Firestore ne
    // supporte pas WHERE IN avec >30 valeurs — on chunke (pattern existant).
    //
    // TODO(P2) : charge actuellement TOUT l'historique de paiements de
    // chaque bail actif (pas de borne temporelle) pour TOUS les baux du
    // landlord — OK pour le MVP, mais coûteux en lectures Firestore si le
    // portefeuille grossit (baux anciens avec des dizaines de paiements)
    // alors que seul le mois dû courant (± marge de recouvrement
    // d'intervalle) importe pour `isLeaseLate()`. Borner avec un filtre
    // `periodEnd >= début du mois dû − marge` quand le volume le justifiera.
    final paymentsByLease = <String, List<Payment>>{};
    for (var i = 0; i < leaseIds.length; i += 30) {
      final chunk = leaseIds.sublist(
        i,
        i + 30 > leaseIds.length ? leaseIds.length : i + 30,
      );
      final paymentsQs = await _firestore
          .collection('payments')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .where('leaseId', whereIn: chunk)
          .get();
      for (final d in paymentsQs.docs) {
        final payment = Payment.fromJson(
          firestoreDocToSnakeJson(d.data(), docId: d.id),
        );
        paymentsByLease.putIfAbsent(payment.leaseId, () => []).add(payment);
      }
    }

    final retards = leases
        .where(
          (lease) => isLeaseLate(
            lease: lease,
            payments: paymentsByLease[lease.id] ?? const [],
            now: now,
          ),
        )
        .length;
    _log.fine('fetchRetards: count=$retards');
    return RetardsKpi(count: retards);
  }

  @override
  Future<DocsPendingKpi> fetchDocsPending() async {
    final qs = await _firestore
        .collection('documents')
        .where('landlordId', isEqualTo: _uid)
        .where('deletedAt', isNull: true)
        .where('category', isEqualTo: 'autre')
        .get();
    _log.fine('fetchDocsPending: count=${qs.docs.length}');
    return DocsPendingKpi(count: qs.docs.length);
  }

  @override
  Future<List<MonthlyCollectedRent>> fetchLastMonthsCollectedRent(
    int months,
  ) async {
    assert(months > 0, 'months doit être strictement positif');
    final uid = _uid;
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month - (months - 1), 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    final paymentsQs = await _firestore
        .collection('payments')
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startMonth))
        .where('paidAt', isLessThan: Timestamp.fromDate(nextMonth))
        .get();

    final collectedByMonth = <String, int>{};
    final paymentsCountByMonth = <String, int>{};
    for (final d in paymentsQs.docs) {
      final paidAt = d.data()['paidAt'];
      if (paidAt is! Timestamp) continue;
      final dt = paidAt.toDate();
      final key = _monthKey(dt.year, dt.month);
      final rent = (d.data()['rentAmountCents'] as num?)?.toInt() ?? 0;
      final charges = (d.data()['chargesAmountCents'] as num?)?.toInt() ?? 0;
      collectedByMonth[key] = (collectedByMonth[key] ?? 0) + rent + charges;
      paymentsCountByMonth[key] = (paymentsCountByMonth[key] ?? 0) + 1;
    }

    final result = <MonthlyCollectedRent>[];
    for (var i = months - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = _monthKey(month.year, month.month);
      result.add(
        MonthlyCollectedRent(
          year: month.year,
          month: month.month,
          collectedCents: collectedByMonth[monthKey] ?? 0,
          hasPayments: (paymentsCountByMonth[monthKey] ?? 0) > 0,
        ),
      );
    }
    _log.fine('fetchLastMonthsCollectedRent($months): ${result.length} mois');
    return result;
  }

  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async {
    final results = await Future.wait([
      _fetchRecentPayments(limit),
      _fetchRecentReceipts(limit),
      _fetchRecentDocuments(limit),
    ]);
    final all = results.expand((x) => x).toList();
    all.sort((a, b) => _activityDate(b).compareTo(_activityDate(a)));
    return all.take(limit).toList();
  }

  Future<List<ActivityItem>> _fetchRecentPayments(int limit) async {
    final items = <ActivityItem>[];
    try {
      final qs = await _firestore
          .collection('payments')
          .where('landlordId', isEqualTo: _uid)
          .where('deletedAt', isNull: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      for (final d in qs.docs) {
        final data = d.data();
        final rent = (data['rentAmountCents'] as num?)?.toInt() ?? 0;
        final charges = (data['chargesAmountCents'] as num?)?.toInt() ?? 0;
        final paidAtTs = data['paidAt'];
        final occurredAt = paidAtTs is Timestamp
            ? paidAtTs.toDate()
            : DateTime.now();
        final tenantLastName = (data['tenantLastName'] as String?) ?? '';
        items.add(
          ActivityItem.paymentRecorded(
            paymentId: d.id,
            leaseId: (data['leaseId'] as String?) ?? '',
            tenantName: tenantLastName.isEmpty ? 'Locataire' : tenantLastName,
            amountCents: rent + charges,
            occurredAt: occurredAt,
          ),
        );
      }
    } on FirebaseException catch (e, st) {
      _log.warning('fetchRecentActivity payments error', e, st);
    }
    return items;
  }

  Future<List<ActivityItem>> _fetchRecentReceipts(int limit) async {
    final items = <ActivityItem>[];
    try {
      final qs = await _firestore
          .collection('receipts')
          .where('landlordId', isEqualTo: _uid)
          .where('isVoided', isEqualTo: false)
          .orderBy('periodStart', descending: true)
          .limit(limit)
          .get();
      for (final d in qs.docs) {
        final data = d.data();
        final generatedAtTs = data['generatedAt'];
        final occurredAt = generatedAtTs is Timestamp
            ? generatedAtTs.toDate()
            : DateTime.now();
        final periodStart = data['periodStart'];
        final periodEnd = data['periodEnd'];
        // Sentinel FR — pas de BuildContext ici (couche data/). Détecté et
        // relocalisé côté présentation par RecentActivitySection (FEAT-043,
        // même pattern que LeaseListItemDisplayL10n).
        String periodLabel = kUnknownPeriodLabelSentinel;
        if (periodStart is Timestamp && periodEnd is Timestamp) {
          final s = periodStart.toDate().toIso8601String().substring(0, 10);
          final e = periodEnd.toDate().toIso8601String().substring(0, 10);
          periodLabel = '$s → $e';
        }
        items.add(
          ActivityItem.receiptGenerated(
            receiptId: d.id,
            leaseId: (data['leaseId'] as String?) ?? '',
            periodLabel: periodLabel,
            totalCents: (data['totalCents'] as num?)?.toInt() ?? 0,
            occurredAt: occurredAt,
          ),
        );
      }
    } on FirebaseException catch (e, st) {
      _log.warning('fetchRecentActivity receipts error', e, st);
    }
    return items;
  }

  Future<List<ActivityItem>> _fetchRecentDocuments(int limit) async {
    final items = <ActivityItem>[];
    try {
      final qs = await _firestore
          .collection('documents')
          .where('landlordId', isEqualTo: _uid)
          .where('deletedAt', isNull: true)
          .orderBy('uploadedAt', descending: true)
          .limit(limit)
          .get();
      for (final d in qs.docs) {
        final data = d.data();
        final createdAtTs = data['createdAt'] ?? data['uploadedAt'];
        final occurredAt = createdAtTs is Timestamp
            ? createdAtTs.toDate()
            : DateTime.now();
        items.add(
          ActivityItem.documentUploaded(
            documentId: d.id,
            leaseId: (data['leaseId'] as String?) ?? '',
            categoryLabel: (data['category'] as String?) ?? 'document',
            filename: (data['filename'] as String?) ?? 'Fichier',
            sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
            occurredAt: occurredAt,
          ),
        );
      }
    } on FirebaseException catch (e, st) {
      _log.warning('fetchRecentActivity documents error', e, st);
    }
    return items;
  }

  @override
  Future<bool> isLandlordOnboarding() async {
    final uid = _uid;
    final results = await Future.wait([
      _firestore
          .collection('properties')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .limit(1)
          .get(),
      _firestore
          .collection('tenants')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .limit(1)
          .get(),
      _firestore
          .collection('leases')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .limit(1)
          .get(),
    ]);
    final isEmpty = results.every((qs) => qs.docs.isEmpty);
    _log.fine('isLandlordOnboarding=$isEmpty');
    return isEmpty;
  }

  @override
  Future<OnboardingProgress> fetchOnboardingProgress() async {
    final uid = _uid;

    Query<Map<String, dynamic>> owned(String col) => _firestore
        .collection(col)
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .limit(1);

    final results = await Future.wait([
      owned('properties').get(),
      owned('tenants').get(),
      owned('leases').get(),
      owned('payments').get(),
      // receipts : collection immuable read-only (pas de deletedAt) ; un
      // receipt compte même s'il est ensuite isVoided — l'aha, c'est de
      // l'avoir généré.
      _firestore
          .collection('receipts')
          .where('landlordId', isEqualTo: uid)
          .limit(1)
          .get(),
    ]);

    final leaseDocs = results[2].docs;
    return OnboardingProgress(
      hasProperty: results[0].docs.isNotEmpty,
      hasTenant: results[1].docs.isNotEmpty,
      hasLease: leaseDocs.isNotEmpty,
      hasPayment: results[3].docs.isNotEmpty,
      hasReceipt: results[4].docs.isNotEmpty,
      firstLeaseId: leaseDocs.isNotEmpty ? leaseDocs.first.id : null,
    );
  }

  static DateTime _activityDate(ActivityItem item) => item.when(
    paymentRecorded: (p0, p1, p2, p3, d) => d,
    receiptGenerated: (p0, p1, p2, p3, d) => d,
    documentUploaded: (p0, p1, p2, p3, p4, d) => d,
  );
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => FirestoreDashboardRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
  ),
);

/// Clé `"YYYY-MM"` utilisée pour indexer des montants par mois calendaire.
String _monthKey(int year, int month) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
