import 'package:flutter/material.dart';

import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../domain/receipt.dart';
import 'receipt_card.dart';

/// Vue timeline verticale des quittances, groupées par année.
///
/// Chaque année est présentée sous un header séparateur. Chaque quittance
/// est affichée via [ReceiptCard] (spec 2026-09-29 — carte « chiffre clé »
/// partagée avec la vue Cards).
///
/// Fallback non-sticky pour le header année (évite la friction
/// [SliverPersistentHeader] sur Flutter Web — cf. plan Phase 4 §Risques).
class ReceiptsTimelineView extends StatelessWidget {
  const ReceiptsTimelineView({
    super.key,
    required this.receipts,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
    this.propertyColorKey,
  });

  final List<Receipt> receipts;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

  /// Couleur d'identité du bien lié — cf. `ReceiptCard.propertyColorKey`.
  final PropertyColorKey? propertyColorKey;

  /// Vue squelette de chargement (6 placeholders).
  static Widget loading() => const _TimelineLoadingView();

  @override
  Widget build(BuildContext context) {
    // Grouper par année (tri DESC déjà appliqué par le repository).
    final grouped = _groupByYear(receipts);
    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    // Construire la liste plate d'items (headers + éléments).
    final items = <_TimelineListItem>[];
    for (final year in years) {
      items.add(_TimelineListItem.yearHeader(year));
      for (final receipt in grouped[year]!) {
        items.add(_TimelineListItem.receipt(receipt));
      }
    }

    return ListView.builder(
      key: const Key('receipts_timeline'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isHeader) {
          return _YearHeader(year: item.year!);
        }
        return _ReceiptTimelineItem(
          receipt: item.receipt!,
          leaseId: leaseId,
          tenantEmail: tenantEmail,
          tenantFirstName: tenantFirstName,
          propertyAddress: propertyAddress,
          landlordFullName: landlordFullName,
          propertyColorKey: propertyColorKey,
        );
      },
    );
  }

  static Map<int, List<Receipt>> _groupByYear(List<Receipt> receipts) {
    final map = <int, List<Receipt>>{};
    for (final r in receipts) {
      final year = r.periodStart.year;
      map.putIfAbsent(year, () => []).add(r);
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Modèle interne pour la liste plate
// ---------------------------------------------------------------------------

class _TimelineListItem {
  const _TimelineListItem._({required this.isHeader, this.year, this.receipt});

  factory _TimelineListItem.yearHeader(int year) =>
      _TimelineListItem._(isHeader: true, year: year);

  factory _TimelineListItem.receipt(Receipt r) =>
      _TimelineListItem._(isHeader: false, receipt: r);

  final bool isHeader;
  final int? year;
  final Receipt? receipt;
}

// ---------------------------------------------------------------------------
// Header année
// ---------------------------------------------------------------------------

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant,
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$year',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Élément de timeline
// ---------------------------------------------------------------------------

class _ReceiptTimelineItem extends StatelessWidget {
  const _ReceiptTimelineItem({
    required this.receipt,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
    this.propertyColorKey,
  });

  final Receipt receipt;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;
  final PropertyColorKey? propertyColorKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ReceiptCard(
        receipt: receipt,
        leaseId: leaseId,
        tenantEmail: tenantEmail,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
        landlordFullName: landlordFullName,
        propertyColorKey: propertyColorKey,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vue squelette chargement
// ---------------------------------------------------------------------------

class _TimelineLoadingView extends StatelessWidget {
  const _TimelineLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: 6,
      itemBuilder: (context, index) => const _TimelineSkeletonItem(),
    );
  }
}

class _TimelineSkeletonItem extends StatelessWidget {
  const _TimelineSkeletonItem();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholderColor = theme.colorScheme.outlineVariant.withAlpha(153);
    final radii = theme.extension<AppRadii>() ?? const AppRadii();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(radii.sm),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              width: 120,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            FractionallySizedBox(
              widthFactor: 0.6,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
