import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/ui/cards/summary_card.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/tenant_list_item.dart';
import 'tenant_status_mapper.dart';

/// Carte d'un locataire dans la liste — adaptateur [SummaryCard] (spec
/// 2026-09-29). Avec bail : loyer CC en chiffre clé, action rapide Appeler
/// (ou email si pas de téléphone). Sans bail : action rapide « + Créer un
/// bail ». Menu ⋮ : Voir le bail (si loué) · Envoyer un email (si pas déjà
/// l'action rapide) · Modifier.
class TenantCard extends StatelessWidget {
  const TenantCard({super.key, required this.item, required this.onTap});

  final TenantListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tenant = item.tenant;
    final tenantId = tenant.id;
    final activeLeaseId = item.activeLeaseId;
    final pillData = tenantOccupancyPill(context, item);
    final propertyId = item.currentPropertyId;
    final colorKey = propertyId != null
        ? PropertyColorKey.resolve(
            entityId: propertyId,
            stored: item.currentPropertyColorKey,
          )
        : null;

    final phone = tenant.phone?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasLease = activeLeaseId != null;
    final rent = item.activeLeaseRentCents;
    final emailInQuickAction = hasLease && !hasPhone;

    void openEmail() =>
        _launch(context, Uri(scheme: 'mailto', path: tenant.email));

    Widget emailButton() => SummaryQuickActionButton(
      key: Key('card_email_$tenantId'),
      icon: Icons.mail_outline,
      label: l10n.tenantsEmailButton,
      onPressed: openEmail,
    );

    return SummaryCard(
      onTap: onTap,
      accentColor: colorKey?.resolveColor(context),
      semanticLabel:
          '${tenant.firstName} ${tenant.lastName} — ${pillData.label}',
      title: '${tenant.firstName} ${tenant.lastName}',
      subtitle: hasLease
          ? (item.currentPropertyName ?? l10n.tenantsNoPropertyOccupied)
          : tenant.email,
      keyFigure: hasLease && rent != null
          ? SummaryKeyFigure(
              value: MoneyFormat.formatEurosFromCents(
                rent + (item.activeLeaseChargesCents ?? 0),
              ),
              caption: l10n.commonRentCcPerMonthCaption,
            )
          : null,
      status: StatusPill(
        tone: pillData.tone,
        label: pillData.label,
        icon: pillData.icon,
        size: StatusPillSize.sm,
      ),
      meta: hasLease ? item.activeLeasePeriodLabel : null,
      quickAction: !hasLease
          ? SummaryQuickActionButton(
              key: Key('card_create_lease_$tenantId'),
              icon: Icons.add,
              label: l10n.tenantsCreateLeaseButton,
              onPressed: () => context.push('/leases/new?tenantId=$tenantId'),
            )
          : hasPhone
          ? SummaryQuickActionButton(
              key: Key('card_call_$tenantId'),
              icon: Icons.call_outlined,
              label: l10n.tenantsCallButton,
              onPressed: () => _launch(
                context,
                Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), '')),
              ),
            )
          : emailButton(),
      menuKey: Key('tenant_menu_$tenantId'),
      menuItems: [
        if (hasLease)
          SummaryMenuItem(
            key: Key('card_view_lease_$tenantId'),
            label: l10n.tenantsViewLeaseButton,
            onSelected: () => context.push('/leases/$activeLeaseId'),
          ),
        if (!emailInQuickAction)
          SummaryMenuItem(
            key: Key('menu_email_$tenantId'),
            label: l10n.tenantsEmailButton,
            onSelected: openEmail,
          ),
        SummaryMenuItem(
          key: Key('card_edit_tenant_$tenantId'),
          label: l10n.commonEdit,
          onSelected: () => context.push('/tenants/$tenantId/edit'),
        ),
      ],
    );
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = context.l10n.tenantsLaunchFailed;
    var ok = false;
    try {
      ok = await launchUrl(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
