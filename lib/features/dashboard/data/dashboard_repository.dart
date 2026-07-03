import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../domain/activity_item.dart';
import '../domain/dashboard_kpi.dart';
import '../domain/monthly_amount.dart';

final _log = Logger('DashboardRepository');

/// Repository dashboard — toutes les méthodes sont des SELECT (lecture seule).
///
/// Contrairement à Supabase RLS où le filtre `landlord_id = auth.uid()` était
/// implicite, ici on doit le passer explicitement dans chaque `where()`. Le
/// rules Firestore les enforce, mais sans le filtre client la query throw.
abstract interface class DashboardRepository {
  Future<LoyersMoisKpi> fetchLoyersMois();
  Future<RetardsKpi> fetchRetards();
  Future<RenouvellementsKpi> fetchRenouvellements();
  Future<DocsPendingKpi> fetchDocsPending();

  /// Montants mensuels encaissé/dû sur les [months] derniers mois
  /// (fenêtre glissante : mois courant inclus, donc `now-(months-1) → now`).
  Future<List<MonthlyAmount>> fetchLastMonthsAmounts(int months);
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5});
  Future<bool> isLandlordOnboarding();
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
    final cutoff = now.subtract(const Duration(days: 35));

    final leasesQs = await _firestore
        .collection('leases')
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .where('status', isEqualTo: 'active')
        .where('startDate', isLessThanOrEqualTo: Timestamp.fromDate(cutoff))
        .get();

    if (leasesQs.docs.isEmpty) return const RetardsKpi(count: 0);

    final leaseIds = leasesQs.docs.map((d) => d.id).toList();

    // Pour chaque lease, on cherche le dernier paiement.
    // Firestore ne supporte pas WHERE IN avec >30 valeurs — on chunke.
    final lastPaymentByLease = <String, DateTime>{};
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
          .orderBy('paidAt', descending: true)
          .get();
      for (final d in paymentsQs.docs) {
        final leaseId = d.data()['leaseId'] as String?;
        if (leaseId == null) continue;
        if (lastPaymentByLease.containsKey(leaseId)) continue;
        final paidAt = d.data()['paidAt'];
        if (paidAt is Timestamp) {
          lastPaymentByLease[leaseId] = paidAt.toDate();
        }
      }
    }

    int retards = 0;
    for (final leaseId in leaseIds) {
      final lastPaid = lastPaymentByLease[leaseId];
      if (lastPaid == null || lastPaid.isBefore(cutoff)) {
        retards++;
      }
    }
    _log.fine('fetchRetards: count=$retards');
    return RetardsKpi(count: retards);
  }

  @override
  Future<RenouvellementsKpi> fetchRenouvellements() async {
    final uid = _uid;
    final today = DateTime.now();
    final in30Days = today.add(const Duration(days: 30));

    final qs = await _firestore
        .collection('leases')
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .where('status', isEqualTo: 'active')
        .where('endDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('endDate', isLessThanOrEqualTo: Timestamp.fromDate(in30Days))
        .get();
    _log.fine('fetchRenouvellements: count=${qs.docs.length}');
    return RenouvellementsKpi(count: qs.docs.length);
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
  Future<List<MonthlyAmount>> fetchLastMonthsAmounts(int months) async {
    assert(months > 0, 'months doit être strictement positif');
    final uid = _uid;
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month - (months - 1), 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    final (paymentsQs, leasesQs) = await (
      _firestore
          .collection('payments')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .where(
            'paidAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startMonth),
          )
          .where('paidAt', isLessThan: Timestamp.fromDate(nextMonth))
          .get(),
      _firestore
          .collection('leases')
          .where('landlordId', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .where('status', isEqualTo: 'active')
          .get(),
    ).wait;

    final encaissedByMonth = <String, int>{};
    for (final d in paymentsQs.docs) {
      final paidAt = d.data()['paidAt'];
      if (paidAt is! Timestamp) continue;
      final dt = paidAt.toDate();
      final key =
          '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}';
      final rent = (d.data()['rentAmountCents'] as num?)?.toInt() ?? 0;
      final charges = (d.data()['chargesAmountCents'] as num?)?.toInt() ?? 0;
      encaissedByMonth[key] = (encaissedByMonth[key] ?? 0) + rent + charges;
    }

    final result = <MonthlyAmount>[];
    for (var i = months - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey =
          '${month.year.toString().padLeft(4, '0')}-'
          '${month.month.toString().padLeft(2, '0')}';

      int due = 0;
      for (final d in leasesQs.docs) {
        final startDate = d.data()['startDate'];
        if (startDate is! Timestamp) continue;
        if (startDate.toDate().isAfter(month)) continue;
        final rent = (d.data()['rentAmountCents'] as num?)?.toInt() ?? 0;
        final charges = (d.data()['chargesAmountCents'] as num?)?.toInt() ?? 0;
        due += rent + charges;
      }
      result.add(
        MonthlyAmount(
          year: month.year,
          month: month.month,
          encaissedCents: encaissedByMonth[monthKey] ?? 0,
          dueCents: due,
        ),
      );
    }
    _log.fine('fetchLastMonthsAmounts($months): ${result.length} mois');
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
        String periodLabel = 'Période inconnue';
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

  static DateTime _activityDate(ActivityItem item) => item.when(
    paymentRecorded: (p0, p1, p2, p3, d) => d,
    receiptGenerated: (p0, p1, p2, p3, d) => d,
    documentUploaded: (p0, p1, p2, p3, p4, d) => d,
  );
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => FirestoreDashboardRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  ),
);
