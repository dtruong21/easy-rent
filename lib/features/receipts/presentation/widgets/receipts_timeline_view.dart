import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../domain/receipt.dart';
import 'receipt_actions_menu.dart';
import 'receipt_status_mapper.dart';

/// Vue timeline verticale des quittances, groupées par année.
///
/// Chaque année est présentée sous un header séparateur.
/// Chaque quittance est affichée comme un élément de timeline avec :
/// - Marqueur cercle coloré selon le tone du statut.
/// - Ligne verticale [outlineVariant].
/// - Période (mois + année), [StatusPill], montant, secondaryLine, actions.
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
  });

  final List<Receipt> receipts;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

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
      final yearReceipts = grouped[year]!;
      for (var i = 0; i < yearReceipts.length; i++) {
        items.add(
          _TimelineListItem.receipt(
            yearReceipts[i],
            isLast: i == yearReceipts.length - 1,
          ),
        );
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
          isLast: item.isLast,
          leaseId: leaseId,
          tenantEmail: tenantEmail,
          tenantFirstName: tenantFirstName,
          propertyAddress: propertyAddress,
          landlordFullName: landlordFullName,
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
  const _TimelineListItem._({
    required this.isHeader,
    this.year,
    this.receipt,
    this.isLast = false,
  });

  factory _TimelineListItem.yearHeader(int year) =>
      _TimelineListItem._(isHeader: true, year: year);

  factory _TimelineListItem.receipt(Receipt r, {required bool isLast}) =>
      _TimelineListItem._(isHeader: false, receipt: r, isLast: isLast);

  final bool isHeader;
  final int? year;
  final Receipt? receipt;
  final bool isLast;
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
    required this.isLast,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
  });

  final Receipt receipt;
  final bool isLast;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pillData = receiptStatusPill(context, receipt);
    final markerColor = _toneColor(context, pillData.tone);
    final periodLabel = receiptPeriodMonthYear(receipt);
    final secondary = receiptSecondaryLine(context, receipt);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Colonne gauche : marqueur + ligne verticale.
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 4),
                _TimelineMarker(color: markerColor),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Contenu principal.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _TimelineItemContent(
                receipt: receipt,
                pillData: pillData,
                periodLabel: periodLabel,
                secondary: secondary,
                leaseId: leaseId,
                tenantEmail: tenantEmail,
                tenantFirstName: tenantFirstName,
                propertyAddress: propertyAddress,
                landlordFullName: landlordFullName,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _toneColor(BuildContext context, StatusPillTone tone) {
    final appColors = Theme.of(context).extension<AppColors>();
    final colors = (appColors ?? AppColors.light).statusFor(tone);
    return colors.solid;
  }
}

// ---------------------------------------------------------------------------
// Marqueur cercle coloré
// ---------------------------------------------------------------------------

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ---------------------------------------------------------------------------
// Contenu d'un élément timeline
// ---------------------------------------------------------------------------

class _TimelineItemContent extends StatelessWidget {
  const _TimelineItemContent({
    required this.receipt,
    required this.pillData,
    required this.periodLabel,
    required this.secondary,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
  });

  final Receipt receipt;
  final ReceiptStatusPillData pillData;
  final String periodLabel;
  final String secondary;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radii = theme.extension<AppRadii>() ?? const AppRadii();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radii.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : période + pill + montant + actions.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      periodLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    StatusPill(
                      tone: pillData.tone,
                      label: pillData.label,
                      icon: pillData.icon,
                      size: StatusPillSize.sm,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                receipt.totalEuros,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              ReceiptActionsMenu(
                key: Key('actions_${receipt.id}'),
                receipt: receipt,
                leaseId: leaseId,
                tenantEmail: tenantEmail,
                tenantFirstName: tenantFirstName,
                propertyAddress: propertyAddress,
                landlordFullName: landlordFullName,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Ligne 2 : secondaryLine.
          Text(
            secondary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Ligne 3 (optionnelle) : motif d'annulation.
          if (receipt.isVoided && receipt.voidedReason != null) ...[
            const SizedBox(height: 2),
            Text(
              context.l10n.receiptsTimelineVoidReasonPrefix(
                receipt.voidedReason!,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marqueur squelette.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: placeholderColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Contenu squelette.
          Expanded(
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
          ),
        ],
      ),
    );
  }
}
