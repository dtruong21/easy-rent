import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/receipt.dart';
import '../domain/receipt_status_filter.dart';
import 'lease_receipts_provider.dart';

// ---------------------------------------------------------------------------
// Filtre statut
// ---------------------------------------------------------------------------

/// Provider du filtre statut actif, paramétré par [leaseId].
///
/// État local non persisté entre sessions.
/// Initial : [ReceiptStatusFilter.all].
final receiptStatusFilterProvider = StateProvider.family
    .autoDispose<ReceiptStatusFilter, String>(
      (ref, leaseId) => ReceiptStatusFilter.all,
    );

// ---------------------------------------------------------------------------
// Filtre année
// ---------------------------------------------------------------------------

/// Provider de l'année filtrée, paramétré par [leaseId].
///
/// `null` = toutes les années. Défaut : année courante si présente dans la liste.
final receiptYearFilterProvider = StateProvider.family
    .autoDispose<int?, String>((ref, leaseId) => null);

// ---------------------------------------------------------------------------
// Années disponibles (peuplées dynamiquement depuis les données)
// ---------------------------------------------------------------------------

/// Provider de la liste des années disponibles pour le Dropdown.
///
/// Calculé depuis l'ensemble des [Receipt.periodStart.year] uniques, trié DESC.
final receiptAvailableYearsProvider = Provider.family
    .autoDispose<List<int>, String>((ref, leaseId) {
      final asyncReceipts = ref.watch(leaseReceiptsProvider(leaseId));
      final receipts = asyncReceipts.valueOrNull ?? [];
      final years = receipts.map((r) => r.periodStart.year).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      return years;
    });

// ---------------------------------------------------------------------------
// Prédicat + compteurs statut
// ---------------------------------------------------------------------------

/// Vrai si [r] correspond au filtre de statut (règles inchangées).
bool receiptMatchesStatus(Receipt r, ReceiptStatusFilter f) => switch (f) {
  ReceiptStatusFilter.all => true,
  ReceiptStatusFilter.sent => r.hasBeenShared && !r.isVoided,
  ReceiptStatusFilter.paid => r.paymentIds.isNotEmpty && !r.isVoided,
  ReceiptStatusFilter.voided => r.isVoided,
};

/// Compteurs par statut, restreints à [year] quand il est défini.
Map<ReceiptStatusFilter, int> receiptStatusCounts(
  List<Receipt> receipts,
  int? year,
) {
  final inYear = year == null
      ? receipts
      : receipts.where((r) => r.periodStart.year == year).toList();
  return {
    for (final f in ReceiptStatusFilter.values)
      f: inYear.where((r) => receiptMatchesStatus(r, f)).length,
  };
}

/// Compteurs des puces — `null` tant que la liste n'est pas chargée. Restreint
/// à l'année sélectionnée ([receiptYearFilterProvider]).
final receiptStatusCountsProvider = Provider.family
    .autoDispose<Map<ReceiptStatusFilter, int>?, String>((ref, leaseId) {
      final receipts = ref.watch(leaseReceiptsProvider(leaseId)).valueOrNull;
      final year = ref.watch(receiptYearFilterProvider(leaseId));
      return receipts == null ? null : receiptStatusCounts(receipts, year);
    });

// ---------------------------------------------------------------------------
// Liste filtrée (statut + année)
// ---------------------------------------------------------------------------

/// Provider dérivé — liste des quittances filtrée selon le statut et l'année.
///
/// Filtrage client-side (200 items max — OK en mémoire).
/// Re-calcule automatiquement à chaque changement de filtre ou de liste.
final filteredReceiptsProvider = Provider.family
    .autoDispose<AsyncValue<List<Receipt>>, String>((ref, leaseId) {
      final asyncReceipts = ref.watch(leaseReceiptsProvider(leaseId));
      final filter = ref.watch(receiptStatusFilterProvider(leaseId));
      final yearFilter = ref.watch(receiptYearFilterProvider(leaseId));

      return asyncReceipts.whenData((receipts) {
        var filtered = receipts;

        // Filtre par statut.
        if (filter != ReceiptStatusFilter.all) {
          filtered = filtered
              .where((r) => receiptMatchesStatus(r, filter))
              .toList();
        }

        // Filtre par année.
        if (yearFilter != null) {
          filtered = filtered
              .where((r) => r.periodStart.year == yearFilter)
              .toList();
        }

        return filtered;
      });
    });
