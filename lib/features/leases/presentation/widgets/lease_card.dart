import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/ui/cards/summary_card.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/lease.dart';
import '../../domain/lease_list_item.dart';
import '../lease_list_item_display_l10n.dart';
import 'lease_status_mapper.dart';

/// Carte d'un bail dans la liste — adaptateur [SummaryCard] (spec
/// 2026-09-29). Chiffre clé : loyer CC. Statut : pastille bail (actif / à
/// renouveler / en retard / terminé). Action rapide : « + Paiement ». Menu
/// ⋮ : Quittances · Régulariser les charges (si applicable, FEAT-030/042) ·
/// Modifier.
class LeaseCard extends StatelessWidget {
  const LeaseCard({super.key, required this.item, required this.onTap});

  final LeaseListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lease = item.lease;
    final pillData = leaseStatusPill(context, lease, isLate: item.isLate);
    final colorKey = PropertyColorKey.resolve(
      entityId: lease.propertyId,
      stored: item.propertyColorKey,
    );

    return SummaryCard(
      onTap: onTap,
      accentColor: colorKey.resolveColor(context),
      semanticLabel: l10n.leasesCardSemanticLabel(
        item.displayPropertyName(context),
        item.displayTenantName(context),
      ),
      title: item.displayPropertyName(context),
      subtitle: item.displayTenantName(context),
      keyFigure: SummaryKeyFigure(
        value: MoneyFormat.formatEurosFromCents(lease.totalAmountCents),
        caption: l10n.commonRentCcPerMonthCaption,
      ),
      status: StatusPill(
        tone: pillData.tone,
        label: pillData.label,
        icon: pillData.icon,
        size: StatusPillSize.sm,
      ),
      meta: _formatPeriod(context, lease.startDate, lease.endDate),
      quickAction: SummaryQuickActionButton(
        key: Key('card_add_payment_${lease.id}'),
        icon: Icons.add,
        label: l10n.leasesCardPaymentButton,
        onPressed: () => context.push('/leases/${lease.id}/payments/new'),
      ),
      menuKey: Key('lease_menu_${lease.id}'),
      menuItems: [
        SummaryMenuItem(
          key: Key('card_receipts_${lease.id}'),
          label: l10n.leasesCardReceiptsButton,
          onSelected: () => context.push('/leases/${lease.id}/receipts'),
        ),
        // Gate légal inchangé (FEAT-030/042) : mode provisions uniquement.
        if (lease.canRegularizeCharges)
          SummaryMenuItem(
            key: const Key('menu_item_regularize_charges'),
            label: l10n.leasesRegularizeChargesMenuItem,
            onSelected: () =>
                context.push('/leases/${lease.id}?action=regularize'),
          ),
        SummaryMenuItem(
          key: Key('card_edit_lease_${lease.id}'),
          label: l10n.commonEdit,
          onSelected: () => context.push('/leases/${lease.id}/edit'),
        ),
      ],
    );
  }

  String _formatPeriod(
    BuildContext context,
    DateTime startDate,
    DateTime? endDate,
  ) {
    final l10n = context.l10n;
    final start = FrenchDate.format(startDate);
    if (endDate == null) {
      return l10n.leasesCardPeriodOpenEnded(start);
    }
    final end = FrenchDate.format(endDate);
    final years = (endDate.difference(startDate).inDays / 365.25).round().abs();
    if (years > 0) {
      return l10n.leasesCardPeriodWithYears(start, end, years);
    }
    return l10n.leasesCardPeriod(start, end);
  }
}
