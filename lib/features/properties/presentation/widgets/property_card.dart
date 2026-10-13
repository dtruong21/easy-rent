import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/ui/cards/summary_card.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/property_list_item.dart';
import 'property_status_mapper.dart';
import 'property_type_l10n.dart';

/// Carte d'un bien dans la liste — adaptateur [SummaryCard] (spec
/// 2026-09-29). Loué : loyer CC en chiffre clé ; vacant : action rapide
/// « Créer un bail ». Menu ⋮ : Voir le bail (si loué) · Modifier.
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.item, required this.onTap});

  final PropertyListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final property = item.property;
    final propertyId = property.id;
    final activeLeaseId = item.activeLeaseId;
    final pillData = propertyOccupancyPill(item, context);
    final colorKey = PropertyColorKey.resolve(
      entityId: propertyId,
      stored: property.colorKey,
    );
    final surfaceSuffix = property.surfaceM2 != null
        ? ' · ${l10n.propertiesSurfaceValue(property.surfaceM2!.toStringAsFixed(property.surfaceM2! % 1 == 0 ? 0 : 2))}'
        : '';
    final rentCc = item.currentRentCcCents;

    return SummaryCard(
      onTap: onTap,
      accentColor: colorKey.resolveColor(context),
      semanticLabel: l10n.propertiesCardSemanticLabel(
        property.name,
        pillData.label,
      ),
      title: property.name,
      subtitle: item.currentTenantName ?? l10n.propertiesNoTenant,
      keyFigure: rentCc == null
          ? null
          : SummaryKeyFigure(
              value: MoneyFormat.formatEurosFromCents(rentCc),
              caption: l10n.commonRentCcPerMonthCaption,
            ),
      status: StatusPill(
        tone: pillData.tone,
        label: pillData.label,
        icon: pillData.icon,
        size: StatusPillSize.sm,
      ),
      meta:
          '${property.address} · ${property.type.label(context)}$surfaceSuffix',
      quickAction: activeLeaseId == null
          ? SummaryQuickActionButton(
              key: Key('card_create_lease_$propertyId'),
              icon: Icons.add,
              label: l10n.propertiesCreateLease,
              onPressed: () =>
                  context.push('/leases/new?propertyId=$propertyId'),
            )
          : null,
      menuKey: Key('property_menu_$propertyId'),
      menuItems: [
        if (activeLeaseId != null)
          SummaryMenuItem(
            key: Key('card_view_lease_$propertyId'),
            label: l10n.propertiesViewLease,
            onSelected: () => context.push('/leases/$activeLeaseId'),
          ),
        SummaryMenuItem(
          key: Key('card_edit_property_$propertyId'),
          label: l10n.commonEdit,
          onSelected: () => context.push('/properties/$propertyId/edit'),
        ),
      ],
    );
  }
}
