import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/entity_card.dart';
import '../../../../core/ui/cards/entity_card_density.dart';
import '../../../../core/ui/cards/entity_card_header.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../../properties/presentation/widgets/property_color_dot.dart';
import '../../domain/tenant_list_item.dart';
import 'tenant_status_mapper.dart';

/// Card v2 représentant un locataire dans la liste.
///
/// Utilise [EntityCard] pour le layout cohérent avec les autres entités.
/// Header : nom complet + [StatusPill] occupation (Actif / Sans bail).
/// Body : téléphone, bien occupé, période bail.
/// Footer : "Voir le bail" ou "Créer un bail" (contextuel) + "Modifier".
///
/// Le tap sur la carte entière navigue vers le détail du locataire.
class TenantCard extends StatelessWidget {
  const TenantCard({super.key, required this.item, required this.onTap});

  final TenantListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tenant = item.tenant;
    final pillData = tenantOccupancyPill(context, item);
    final propertyId = item.currentPropertyId;
    final colorKey = propertyId != null
        ? PropertyColorKey.resolve(
            entityId: propertyId,
            stored: item.currentPropertyColorKey,
          )
        : null;

    return EntityCard(
      onTap: onTap,
      density: EntityCardDensity.compact,
      semanticLabel:
          '${tenant.firstName} ${tenant.lastName} — ${pillData.label}',
      header: EntityCardHeader(
        leading: colorKey != null ? PropertyColorDot(colorKey: colorKey) : null,
        title: Text(
          '${tenant.firstName} ${tenant.lastName}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          tenant.email,
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
          _TenantCardRow(icon: Icons.phone_outlined, text: tenant.phone ?? '—'),
          const SizedBox(height: 4),
          _TenantCardRow(
            icon: Icons.home_outlined,
            text: item.currentPropertyName ?? l10n.tenantsNoPropertyOccupied,
          ),
          const SizedBox(height: 4),
          _TenantCardRow(
            icon: Icons.calendar_today_outlined,
            text: item.activeLeasePeriodLabel ?? '—',
          ),
        ],
      ),
      footer: _TenantCardFooter(item: item),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets privés
// ---------------------------------------------------------------------------

class _TenantCardRow extends StatelessWidget {
  const _TenantCardRow({required this.icon, required this.text});

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

class _TenantCardFooter extends StatelessWidget {
  const _TenantCardFooter({required this.item});

  final TenantListItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tenantId = item.tenant.id;
    final activeLeaseId = item.activeLeaseId;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (activeLeaseId != null)
          OutlinedButton.icon(
            key: Key('card_view_lease_$tenantId'),
            onPressed: () => context.push('/leases/$activeLeaseId'),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: Text(l10n.tenantsViewLeaseButton),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
          )
        else
          OutlinedButton.icon(
            key: Key('card_create_lease_$tenantId'),
            onPressed: () => context.push('/leases/new?tenantId=$tenantId'),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.tenantsCreateLeaseButton),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        OutlinedButton.icon(
          key: Key('card_edit_tenant_$tenantId'),
          onPressed: () => context.push('/tenants/$tenantId/edit'),
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
