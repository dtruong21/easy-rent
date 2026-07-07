import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../application/lease_receipts_provider.dart';
import '../domain/receipt.dart';
import 'widgets/receipts_timeline_view.dart';

final _log = Logger('ReceiptsListSection');

/// Section "Quittances émises" à intégrer dans [LeaseDetailPage].
///
/// Affiche la liste des quittances triées par [period_start DESC].
/// Inclut les quittances annulées avec badge "Annulée" pour traçabilité.
///
/// Pour activer le bouton de partage, passer [tenantEmail], [tenantFirstName],
/// [propertyAddress] et [landlordFullName].
class ReceiptsListSection extends ConsumerWidget {
  const ReceiptsListSection({
    super.key,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
  });

  final String leaseId;

  /// Email du locataire — nécessaire pour activer le bouton de partage.
  final String? tenantEmail;

  /// Prénom du locataire — pour le corps du message de partage.
  final String tenantFirstName;

  /// Adresse du logement — pour le corps du message de partage.
  final String propertyAddress;

  /// Nom complet du bailleur — pour la signature du message de partage.
  final String landlordFullName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReceipts = ref.watch(leaseReceiptsProvider(leaseId));
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.receiptsSectionTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            asyncReceipts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) {
                _log.warning('Erreur chargement quittances', e);
                return Text(
                  l10n.receiptsSectionErrorMessage,
                  style: TextStyle(color: theme.colorScheme.error),
                );
              },
              data: (receipts) {
                if (receipts.isEmpty) {
                  return const _EmptyReceiptsHint();
                }
                return _ReceiptsList(
                  receipts: receipts,
                  leaseId: leaseId,
                  tenantEmail: tenantEmail,
                  tenantFirstName: tenantFirstName,
                  propertyAddress: propertyAddress,
                  landlordFullName: landlordFullName,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptsList extends StatelessWidget {
  const _ReceiptsList({
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

  @override
  Widget build(BuildContext context) {
    // Affiche les 3 premières quittances max avec la timeline compacte.
    // Pour la liste complète, naviguer vers /leases/:id/receipts.
    final preview = receipts.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: preview.length * 90.0,
          child: ReceiptsTimelineView(
            receipts: preview,
            leaseId: leaseId,
            tenantEmail: tenantEmail,
            tenantFirstName: tenantFirstName,
            propertyAddress: propertyAddress,
            landlordFullName: landlordFullName,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('btn_see_all_receipts'),
            onPressed: () => context.go('/leases/$leaseId/receipts'),
            icon: const Icon(Icons.list_alt_outlined, size: 18),
            label: Text(context.l10n.receiptsSectionSeeAllButton),
          ),
        ),
      ],
    );
  }
}

class _EmptyReceiptsHint extends StatelessWidget {
  const _EmptyReceiptsHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        context.l10n.receiptsSectionEmptyHint,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
