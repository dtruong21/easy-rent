import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../leases/application/lease_detail_provider.dart';
import '../../../properties/application/property_detail_provider.dart';
import '../../../tenants/application/tenant_detail_provider.dart';
import '../../application/lease_receipts_provider.dart';
import '../../domain/receipt.dart';

/// Bandeau contextuel compact en tête de la page Quittances.
///
/// Affiche :
/// - Nom du bien + adresse (cliquable → détail propriété).
/// - Nom du locataire (cliquable → détail locataire).
/// - Période du bail + loyer CC/mois.
/// - Compteurs : X quittances générées · Y envoyées.
///
/// Affiche des squelettes si les données asynchrones ne sont pas encore résolues.
class LeaseContextBanner extends ConsumerWidget {
  const LeaseContextBanner({super.key, required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLease = ref.watch(leaseDetailProvider(leaseId));
    final tenantId = asyncLease.valueOrNull?.tenantId;
    final propertyId = asyncLease.valueOrNull?.propertyId;

    final asyncTenant = tenantId != null
        ? ref.watch(tenantDetailProvider(tenantId))
        : null;
    final asyncProperty = propertyId != null
        ? ref.watch(propertyDetailProvider(propertyId))
        : null;
    final asyncReceipts = ref.watch(leaseReceiptsProvider(leaseId));

    final lease = asyncLease.valueOrNull;
    final tenant = asyncTenant?.valueOrNull;
    final property = asyncProperty?.valueOrNull;
    final receipts = asyncReceipts.valueOrNull ?? <Receipt>[];

    final isLoading = lease == null;

    return _BannerContainer(
      child: isLoading
          ? const _BannerSkeleton()
          : _BannerContent(
              leaseId: leaseId,
              propertyId: propertyId,
              tenantId: tenantId,
              propertyName: property?.name ?? 'Bien en cours de chargement...',
              propertyAddress: property?.address ?? '',
              tenantName: '${tenant?.firstName ?? ''} ${tenant?.lastName ?? ''}'
                  .trim(),
              rentCents: lease.rentAmountCents,
              chargesCents: lease.chargesAmountCents,
              startDate: lease.startDate,
              endDate: lease.endDate,
              totalReceipts: receipts.length,
              sentReceipts: receipts.where((r) => r.hasBeenShared).length,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conteneur commun
// ---------------------------------------------------------------------------

class _BannerContainer extends StatelessWidget {
  const _BannerContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radii = theme.extension<AppRadii>() ?? const AppRadii();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Contenu nominal
// ---------------------------------------------------------------------------

class _BannerContent extends StatelessWidget {
  const _BannerContent({
    required this.leaseId,
    required this.propertyId,
    required this.tenantId,
    required this.propertyName,
    required this.propertyAddress,
    required this.tenantName,
    required this.rentCents,
    required this.chargesCents,
    required this.startDate,
    this.endDate,
    required this.totalReceipts,
    required this.sentReceipts,
  });

  final String leaseId;
  final String? propertyId;
  final String? tenantId;
  final String propertyName;
  final String propertyAddress;
  final String tenantName;
  final int rentCents;
  final int chargesCents;
  final DateTime startDate;
  final DateTime? endDate;
  final int totalReceipts;
  final int sentReceipts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalAmountCents = rentCents + chargesCents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ligne 1 : bien + locataire (cliquables).
        Row(
          children: [
            if (propertyId != null)
              GestureDetector(
                onTap: () => context.push('/properties/$propertyId'),
                child: Text(
                  propertyAddress.isNotEmpty
                      ? '$propertyName · $propertyAddress'
                      : propertyName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    color: theme.colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Expanded(
                child: Text(
                  propertyName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // Ligne 2 : locataire + bail + loyer.
        Wrap(
          spacing: 8,
          children: [
            if (tenantId != null && tenantName.isNotEmpty)
              GestureDetector(
                onTap: () => context.push('/tenants/$tenantId'),
                child: Text(
                  tenantName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    decoration: TextDecoration.underline,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Text(
              'Bail ${FrenchDate.format(startDate)}'
              ' → ${endDate != null ? FrenchDate.format(endDate!) : 'CDI'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${MoneyFormat.formatEurosFromCents(totalAmountCents)} CC/mois',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Ligne 3 : compteurs.
        Text(
          '$totalReceipts quittance${totalReceipts != 1 ? 's' : ''} générée${totalReceipts != 1 ? 's' : ''}'
          ' · $sentReceipts envoyée${sentReceipts != 1 ? 's' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Squelette chargement
// ---------------------------------------------------------------------------

class _BannerSkeleton extends StatelessWidget {
  const _BannerSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant.withAlpha(153);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBar(color: color, widthFactor: 0.7, height: 14),
        const SizedBox(height: 6),
        _SkeletonBar(color: color, widthFactor: 0.5, height: 10),
        const SizedBox(height: 6),
        _SkeletonBar(color: color, widthFactor: 0.4, height: 10),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.color,
    required this.widthFactor,
    required this.height,
  });

  final Color color;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
