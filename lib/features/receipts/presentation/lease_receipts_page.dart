import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/cards/card_empty_state.dart';
import '../../../core/ui/cards/view_mode.dart';
import '../../../core/ui/cards/view_mode_provider.dart';
import '../../../core/ui/breakpoints.dart';
import '../../leases/application/lease_detail_provider.dart';
import '../../profile/application/landlord_profile_provider.dart';
import '../../properties/application/property_detail_provider.dart';
import '../../tenants/application/tenant_detail_provider.dart';
import '../application/receipts_filter_provider.dart';
import 'widgets/lease_context_banner.dart';
import 'widgets/receipts_card_view.dart';
import 'widgets/receipts_filter_bar.dart';
import 'widgets/receipts_timeline_view.dart';

final _log = Logger('LeaseReceiptsPage');

/// Page `/leases/:id/receipts` — liste complète des quittances d'un bail.
///
/// Vue par défaut : Timeline verticale groupée par année.
/// Vue alternative : grille de Cards.
/// Filtre statut + filtre année en tête de page.
/// Bandeau contextuel bail au sommet.
class LeaseReceiptsPage extends ConsumerWidget {
  const LeaseReceiptsPage({super.key, required this.leaseId});

  final String leaseId;

  String get _viewModeKey => 'receipts:$leaseId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final asyncFiltered = ref.watch(filteredReceiptsProvider(leaseId));

    // Vue : Timeline (table) par défaut. Sur mobile, force Timeline.
    final viewMode = context.isMobile
        ? ViewMode.table
        : ref.watch(viewModeProvider(_viewModeKey));

    // Charger le contexte pour les actions de partage.
    final asyncLease = ref.watch(leaseDetailProvider(leaseId));
    final tenantId = asyncLease.valueOrNull?.tenantId;
    final propertyId = asyncLease.valueOrNull?.propertyId;

    final asyncTenant = tenantId != null
        ? ref.watch(tenantDetailProvider(tenantId))
        : null;
    final asyncProperty = propertyId != null
        ? ref.watch(propertyDetailProvider(propertyId))
        : null;
    final asyncProfile = ref.watch(landlordProfileProvider);

    final tenantEmail = asyncTenant?.valueOrNull?.email;
    final tenantFirstName = asyncTenant?.valueOrNull?.firstName ?? '';
    final propertyAddress = asyncProperty?.valueOrNull?.address ?? '';
    final landlordFullName = asyncProfile.valueOrNull?.fullName ?? '';

    return Scaffold(
      appBar: AppAppBar(
        title: l10n.receiptsListPageTitle,
        fallbackRoute: '/leases/$leaseId',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bandeau contexte bail.
          LeaseContextBanner(leaseId: leaseId),
          // Barre de filtres.
          ReceiptsFilterBar(leaseId: leaseId),
          // Liste principale.
          Expanded(
            child: asyncFiltered.when(
              loading: () => viewMode == ViewMode.card
                  ? ReceiptsCardView.loading()
                  : ReceiptsTimelineView.loading(),
              error: (e, _) {
                _log.warning('Erreur chargement quittances', e);
                return _ErrorView(
                  onRetry: () =>
                      ref.invalidate(filteredReceiptsProvider(leaseId)),
                );
              },
              data: (receipts) {
                if (receipts.isEmpty) {
                  return CardEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: l10n.receiptsEmptyStateTitle,
                    message: l10n.receiptsEmptyStateMessage,
                    action: FilledButton.icon(
                      key: const Key('btn_go_payments_empty'),
                      onPressed: () =>
                          context.push('/leases/$leaseId/payments/new'),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.receiptsEmptyStateGoPaymentsButton),
                    ),
                  );
                }

                if (viewMode == ViewMode.card) {
                  return ReceiptsCardView(
                    receipts: receipts,
                    leaseId: leaseId,
                    tenantEmail: tenantEmail,
                    tenantFirstName: tenantFirstName,
                    propertyAddress: propertyAddress,
                    landlordFullName: landlordFullName,
                  );
                }

                return ReceiptsTimelineView(
                  receipts: receipts,
                  leaseId: leaseId,
                  tenantEmail: tenantEmail,
                  tenantFirstName: tenantFirstName,
                  propertyAddress: propertyAddress,
                  landlordFullName: landlordFullName,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              l10n.receiptsListErrorTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
