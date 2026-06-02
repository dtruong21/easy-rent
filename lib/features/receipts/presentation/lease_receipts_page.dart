import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../application/lease_receipts_provider.dart';
import '../domain/receipt.dart';
import 'widgets/receipt_list_tile.dart';

final _log = Logger('LeaseReceiptsPage');

/// Page `/leases/:id/receipts` — liste complète des quittances d'un bail.
///
/// Route dédiée pour consulter toutes les quittances (y compris annulées).
/// La [ReceiptsListSection] dans [LeaseDetailPage] offre une vue résumée
/// intégrée ; cette page permet l'accès direct et un affichage complet.
class LeaseReceiptsPage extends ConsumerWidget {
  const LeaseReceiptsPage({super.key, required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReceipts = ref.watch(leaseReceiptsProvider(leaseId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quittances'),
        leading: BackButton(onPressed: () => context.go('/leases/$leaseId')),
      ),
      body: asyncReceipts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          _log.warning('Erreur chargement quittances', e);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Impossible de charger les quittances.',
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(leaseReceiptsProvider(leaseId).notifier)
                        .refresh(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          );
        },
        data: (receipts) {
          if (receipts.isEmpty) {
            return const _EmptyPage();
          }
          return _ReceiptsList(receipts: receipts, leaseId: leaseId);
        },
      ),
    );
  }
}

class _ReceiptsList extends StatelessWidget {
  const _ReceiptsList({required this.receipts, required this.leaseId});

  final List<Receipt> receipts;
  final String leaseId;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: receipts.length,
      separatorBuilder: (context, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final receipt = receipts[index];
        return ReceiptListTile(receipt: receipt, leaseId: leaseId);
      },
    );
  }
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune quittance générée',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Les quittances générées depuis les paiements apparaîtront ici.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
