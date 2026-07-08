import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/entity_card.dart';
import '../../../../core/ui/cards/entity_card_header.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../domain/property_list_item.dart';
import '../../domain/property_type.dart';
import 'property_status_mapper.dart';
import 'property_type_l10n.dart';

/// Card v2 représentant un bien immobilier dans la liste.
///
/// Utilise [EntityCard] pour le layout cohérent avec les autres entités.
/// Header : nom du bien + [StatusPill] occupation (Loué / Vacant).
/// Body : type/surface, locataire courant, loyer CC.
/// Footer : "Voir le bail" ou "Créer un bail" (contextuel) + "Modifier".
///
/// Le tap sur la carte entière navigue vers le détail du bien.
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.item, required this.onTap});

  final PropertyListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final property = item.property;
    final pillData = propertyOccupancyPill(item, context);

    final surfaceSuffix = property.surfaceM2 != null
        ? ' · ${l10n.propertiesSurfaceValue(property.surfaceM2!.toStringAsFixed(property.surfaceM2! % 1 == 0 ? 0 : 2))}'
        : '';

    return EntityCard(
      onTap: onTap,
      semanticLabel: l10n.propertiesCardSemanticLabel(
        property.name,
        pillData.label,
      ),
      header: EntityCardHeader(
        title: Text(
          property.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          property.address,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusPill(
          tone: pillData.tone,
          label: pillData.label,
          icon: pillData.icon,
          size: StatusPillSize.sm,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PropertyCardRow(
            icon: _iconForType(property.type),
            text: '${property.type.label(context)}$surfaceSuffix',
          ),
          const SizedBox(height: 4),
          _PropertyCardRow(
            icon: Icons.person_outline,
            text: item.currentTenantName ?? l10n.propertiesNoTenant,
          ),
          const SizedBox(height: 4),
          _PropertyCardRow(
            icon: Icons.euro_outlined,
            text: item.currentRentLabel ?? '—',
          ),
        ],
      ),
      footer: _PropertyCardFooter(item: item),
    );
  }

  IconData _iconForType(PropertyType type) => switch (type) {
    PropertyType.appartement => Icons.apartment,
    PropertyType.maison => Icons.house,
    PropertyType.studio => Icons.single_bed,
    PropertyType.autre => Icons.home_work,
  };
}

// ---------------------------------------------------------------------------
// Widgets privés
// ---------------------------------------------------------------------------

class _PropertyCardRow extends StatelessWidget {
  const _PropertyCardRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PropertyCardFooter extends StatelessWidget {
  const _PropertyCardFooter({required this.item});

  final PropertyListItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final propertyId = item.property.id;
    final activeLeaseId = item.activeLeaseId;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (activeLeaseId != null)
          OutlinedButton.icon(
            key: Key('card_view_lease_$propertyId'),
            onPressed: () => context.push('/leases/$activeLeaseId'),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: Text(l10n.propertiesViewLease),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
          )
        else
          OutlinedButton.icon(
            key: Key('card_create_lease_$propertyId'),
            onPressed: () => context.push('/leases/new?propertyId=$propertyId'),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.propertiesCreateLease),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        OutlinedButton.icon(
          key: Key('card_edit_property_$propertyId'),
          onPressed: () => context.push('/properties/$propertyId/edit'),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: Text(l10n.commonEdit),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
