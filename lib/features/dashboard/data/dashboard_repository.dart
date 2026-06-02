import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db.dart';
import '../domain/activity_item.dart';
import '../domain/dashboard_kpi.dart';
import '../domain/monthly_amount.dart';

final _log = Logger('DashboardRepository');

/// Contrat du repository dashboard.
///
/// Toutes les méthodes sont des SELECT — aucune mutation.
/// Les filtres RLS (landlord_id = auth.uid()) sont implicites.
abstract interface class DashboardRepository {
  /// Loyers encaissés et théoriques du mois courant.
  Future<LoyersMoisKpi> fetchLoyersMois();

  /// Nombre de baux actifs sans paiement depuis >35 jours.
  Future<RetardsKpi> fetchRetards();

  /// Nombre de baux actifs dont l'échéance est dans ≤30 jours.
  Future<RenouvellementsKpi> fetchRenouvellements();

  /// Nombre de documents de catégorie "autre" (proxy MVP).
  Future<DocsPendingKpi> fetchDocsPending();

  /// Montants encaissés/dus pour chacun des 6 derniers mois (M-5 → M).
  Future<List<MonthlyAmount>> fetchLast6MonthsAmounts();

  /// Dernières 5 actions (paiements, quittances, documents).
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5});

  /// `true` si le bailleur n'a aucun bien + locataire + bail.
  Future<bool> isLandlordOnboarding();
}

// ---------------------------------------------------------------------------
// Implémentation Supabase
// ---------------------------------------------------------------------------

/// Implémentation concrète du [DashboardRepository] via Supabase.
///
/// Chaque méthode correspond à 1 ou 2 requêtes SELECT simples.
/// Les agrégations complexes (6 mois) sont calculées côté Dart pour MVP.
/// P1 : RPC unique `get_dashboard_snapshot()` côté SQL pour perf.
class SupabaseDashboardRepository implements DashboardRepository {
  const SupabaseDashboardRepository();

  // --------------------------------------------------------------------------
  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async {
    final now = DateTime.now();
    // paid_at est de type SQL `date` (YYYY-MM-DD) — on utilise _formatDate pour
    // éviter les faux positifs/négatifs liés au fuseau horaire.
    final monthStart = _formatDate(DateTime(now.year, now.month, 1));
    final monthEnd = _formatDate(DateTime(now.year, now.month + 1, 1));

    // Encaissé : SUM des paiements paid_at dans le mois courant.
    final encaissedResult = await Db.from('payments')
        .select('rent_amount_cents,charges_amount_cents')
        .gte('paid_at', monthStart)
        .lt('paid_at', monthEnd)
        .isFilter('deleted_at', null);

    int encaissed = 0;
    for (final row in encaissedResult) {
      final rent = (row['rent_amount_cents'] as num?)?.toInt() ?? 0;
      final charges = (row['charges_amount_cents'] as num?)?.toInt() ?? 0;
      encaissed += rent + charges;
    }

    // Dû : SUM des loyers+charges des baux actifs.
    final dueResult = await Db.from('leases')
        .select('rent_amount_cents,charges_amount_cents')
        .eq('status', 'active')
        .isFilter('deleted_at', null);

    int due = 0;
    for (final row in dueResult) {
      final rent = (row['rent_amount_cents'] as num?)?.toInt() ?? 0;
      final charges = (row['charges_amount_cents'] as num?)?.toInt() ?? 0;
      due += rent + charges;
    }

    _log.fine('fetchLoyersMois: encaissed=$encaissed due=$due');
    return LoyersMoisKpi(encaissedCents: encaissed, dueCents: due);
  }

  // --------------------------------------------------------------------------
  @override
  Future<RetardsKpi> fetchRetards() async {
    // Approche client-side MVP :
    // 1. Charge les baux actifs récents (démarrés il y a >35j pour éviter faux positifs).
    // 2. Charge les derniers paiements par bail.
    // 3. Compare : si le dernier paiement est >35j ou inexistant → retard.
    final now = DateTime.now();
    // start_date est de type SQL `date` — utiliser _formatDate.
    final cutoffDate = _formatDate(now.subtract(const Duration(days: 35)));

    // Baux actifs non récents (démarrés il y a >35j).
    final leasesResult = await Db.from('leases')
        .select('id,start_date')
        .eq('status', 'active')
        .isFilter('deleted_at', null)
        .lte('start_date', cutoffDate);

    if (leasesResult.isEmpty) {
      return const RetardsKpi(count: 0);
    }

    final leaseIds = leasesResult.map((r) => r['id'] as String).toList();

    // Derniers paiements par bail (non supprimés).
    final paymentsResult = await Db.from('payments')
        .select('lease_id,paid_at')
        .inFilter('lease_id', leaseIds)
        .isFilter('deleted_at', null)
        .order('paid_at', ascending: false);

    // Map leaseId → dernière date de paiement.
    final lastPayment = <String, DateTime>{};
    for (final row in paymentsResult) {
      final leaseId = row['lease_id'] as String;
      if (!lastPayment.containsKey(leaseId)) {
        final paidAtStr = row['paid_at'] as String?;
        if (paidAtStr != null) {
          lastPayment[leaseId] = DateTime.parse(paidAtStr);
        }
      }
    }

    int retards = 0;
    for (final leaseId in leaseIds) {
      final lastPaid = lastPayment[leaseId];
      if (lastPaid == null ||
          lastPaid.isBefore(now.subtract(const Duration(days: 35)))) {
        retards++;
      }
    }

    _log.fine('fetchRetards: count=$retards');
    return RetardsKpi(count: retards);
  }

  // --------------------------------------------------------------------------
  @override
  Future<RenouvellementsKpi> fetchRenouvellements() async {
    final today = DateTime.now();
    final todayStr = _formatDate(today);
    final in30DaysStr = _formatDate(today.add(const Duration(days: 30)));

    final result = await Db.from('leases')
        .select('id')
        .eq('status', 'active')
        .isFilter('deleted_at', null)
        .gte('end_date', todayStr)
        .lte('end_date', in30DaysStr);

    _log.fine('fetchRenouvellements: count=${result.length}');
    return RenouvellementsKpi(count: result.length);
  }

  // --------------------------------------------------------------------------
  @override
  Future<DocsPendingKpi> fetchDocsPending() async {
    final result = await Db.from(
      'documents',
    ).select('id').eq('category', 'autre').isFilter('deleted_at', null);

    _log.fine('fetchDocsPending: count=${result.length}');
    return DocsPendingKpi(count: result.length);
  }

  // --------------------------------------------------------------------------
  @override
  Future<List<MonthlyAmount>> fetchLast6MonthsAmounts() async {
    final now = DateTime.now();
    // Premier jour du mois M-5.
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    // Premier jour du mois M+1 (borne exclue).
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    final sixMonthsAgoStr = _formatDate(sixMonthsAgo);
    final nextMonthStr = _formatDate(nextMonth);

    // Une seule requête pour 6 mois de paiements (required #6 — remplace N+1).
    final (paymentsResult, leasesResult) = await (
      Db.from('payments')
          .select('rent_amount_cents,charges_amount_cents,paid_at')
          .gte('paid_at', sixMonthsAgoStr)
          .lt('paid_at', nextMonthStr)
          .isFilter('deleted_at', null),
      Db.from('leases')
          .select(
            'rent_amount_cents,charges_amount_cents,start_date,end_date,status',
          )
          .eq('status', 'active')
          .isFilter('deleted_at', null),
    ).wait;

    // Groupe les paiements encaissés par 'YYYY-MM'.
    final encaissedByMonth = <String, int>{};
    for (final row in paymentsResult) {
      final paidAt = row['paid_at'] as String?;
      if (paidAt == null || paidAt.length < 7) continue;
      final monthKey = paidAt.substring(0, 7); // 'YYYY-MM'
      final rent = (row['rent_amount_cents'] as num?)?.toInt() ?? 0;
      final charges = (row['charges_amount_cents'] as num?)?.toInt() ?? 0;
      encaissedByMonth[monthKey] =
          (encaissedByMonth[monthKey] ?? 0) + rent + charges;
    }

    // Pour chaque mois M-5 → M, calcule le dû (baux actifs ce mois-là).
    final months = <MonthlyAmount>[];
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthStr = _formatDate(month);
      final monthKey =
          '${month.year.toString().padLeft(4, '0')}-'
          '${month.month.toString().padLeft(2, '0')}';

      int due = 0;
      for (final row in leasesResult) {
        final startDate = row['start_date'] as String? ?? '';
        // Bail actif si start_date ≤ 1er du mois considéré.
        if (startDate.compareTo(monthStr) <= 0) {
          final rent = (row['rent_amount_cents'] as num?)?.toInt() ?? 0;
          final charges = (row['charges_amount_cents'] as num?)?.toInt() ?? 0;
          due += rent + charges;
        }
      }

      months.add(
        MonthlyAmount(
          year: month.year,
          month: month.month,
          encaissedCents: encaissedByMonth[monthKey] ?? 0,
          dueCents: due,
        ),
      );
    }

    _log.fine('fetchLast6MonthsAmounts: ${months.length} mois');
    return months;
  }

  // --------------------------------------------------------------------------
  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async {
    // BLOCKER-3 : fetch 3 sources en parallèle puis tri + take.
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
      final payments = await Db.from('payments')
          .select(
            'id,lease_id,rent_amount_cents,charges_amount_cents,paid_at,'
            'leases!inner(tenants!inner(first_name,last_name))',
          )
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(limit);

      for (final row in payments) {
        final leaseData = row['leases'] as Map<String, dynamic>?;
        final tenantData = leaseData?['tenants'] as Map<String, dynamic>?;
        final firstName = tenantData?['first_name'] as String? ?? '';
        final lastName = tenantData?['last_name'] as String? ?? '';
        final tenantName = '$firstName $lastName'.trim();

        final rent = (row['rent_amount_cents'] as num?)?.toInt() ?? 0;
        final charges = (row['charges_amount_cents'] as num?)?.toInt() ?? 0;
        final paidAtStr = row['paid_at'] as String? ?? '';
        final occurredAt = paidAtStr.isNotEmpty
            ? DateTime.parse(paidAtStr)
            : DateTime.now();

        items.add(
          ActivityItem.paymentRecorded(
            paymentId: row['id'] as String,
            leaseId: row['lease_id'] as String,
            tenantName: tenantName.isEmpty ? 'Locataire' : tenantName,
            amountCents: rent + charges,
            occurredAt: occurredAt,
          ),
        );
      }
    } on PostgrestException catch (e, st) {
      _log.warning('fetchRecentActivity payments error', e, st);
    }
    return items;
  }

  Future<List<ActivityItem>> _fetchRecentReceipts(int limit) async {
    final items = <ActivityItem>[];
    try {
      final receipts = await Db.from('receipts')
          .select(
            'id,lease_id,period_start,period_end,total_cents,generated_at',
          )
          .eq('is_voided', false)
          .order('generated_at', ascending: false)
          .limit(limit);

      for (final row in receipts) {
        final generatedAtStr = row['generated_at'] as String? ?? '';
        final occurredAt = generatedAtStr.isNotEmpty
            ? DateTime.parse(generatedAtStr)
            : DateTime.now();
        final periodStart = row['period_start'] as String? ?? '';
        final periodEnd = row['period_end'] as String? ?? '';
        final periodLabel = periodStart.isNotEmpty
            ? '$periodStart → $periodEnd'
            : 'Période inconnue';

        items.add(
          ActivityItem.receiptGenerated(
            receiptId: row['id'] as String,
            leaseId: row['lease_id'] as String,
            periodLabel: periodLabel,
            totalCents: (row['total_cents'] as num?)?.toInt() ?? 0,
            occurredAt: occurredAt,
          ),
        );
      }
    } on PostgrestException catch (e, st) {
      _log.warning('fetchRecentActivity receipts error', e, st);
    }
    return items;
  }

  Future<List<ActivityItem>> _fetchRecentDocuments(int limit) async {
    final items = <ActivityItem>[];
    try {
      final docs = await Db.from('documents')
          .select('id,lease_id,category,filename,size_bytes,created_at')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(limit);

      for (final row in docs) {
        final createdAtStr = row['created_at'] as String? ?? '';
        final occurredAt = createdAtStr.isNotEmpty
            ? DateTime.parse(createdAtStr)
            : DateTime.now();

        items.add(
          ActivityItem.documentUploaded(
            documentId: row['id'] as String,
            leaseId: row['lease_id'] as String? ?? '',
            categoryLabel: row['category'] as String? ?? 'document',
            filename: row['filename'] as String? ?? 'Fichier',
            sizeBytes: (row['size_bytes'] as num?)?.toInt() ?? 0,
            occurredAt: occurredAt,
          ),
        );
      }
    } on PostgrestException catch (e, st) {
      _log.warning('fetchRecentActivity documents error', e, st);
    }
    return items;
  }

  // --------------------------------------------------------------------------
  @override
  Future<bool> isLandlordOnboarding() async {
    final results = await Future.wait([
      Db.from('properties').select('id').limit(1),
      Db.from('tenants').select('id').limit(1),
      Db.from('leases').select('id').limit(1),
    ]);

    final isEmpty = results.every((r) => (r as List).isEmpty);
    _log.fine('isLandlordOnboarding=$isEmpty');
    return isEmpty;
  }

  // --------------------------------------------------------------------------
  // Helpers privés
  // --------------------------------------------------------------------------

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime _activityDate(ActivityItem item) => item.when(
    paymentRecorded: (p0, p1, p2, p3, d) => d,
    receiptGenerated: (p0, p1, p2, p3, d) => d,
    documentUploaded: (p0, p1, p2, p3, p4, d) => d,
  );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider du repository dashboard.
final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => const SupabaseDashboardRepository(),
);
