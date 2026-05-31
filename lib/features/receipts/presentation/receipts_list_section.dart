import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../application/lease_receipts_provider.dart';
import '../domain/receipt.dart';
import 'widgets/receipt_list_tile.dart';

final _log = Logger('ReceiptsListSection');

/// Section "Quittances émises" à intégrer dans [LeaseDetailPage].
///
/// Affiche la liste des quittances triées par [period_start DESC].
/// Inclut les quittances annulées avec badge "Annulée" pour traçabilité.
class ReceiptsListSection extends ConsumerWidget {
  const ReceiptsListSection({super.key, required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReceipts = ref.watch(leaseReceiptsProvider(leaseId));
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quittances émises', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            asyncReceipts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) {
                _log.warning('Erreur chargement quittances', e);
                return Text(
                  'Erreur lors du chargement des quittances.',
                  style: TextStyle(color: theme.colorScheme.error),
                );
              },
              data: (receipts) {
                if (receipts.isEmpty) {
                  return _EmptyReceiptsHint();
                }
                return _ReceiptsList(receipts: receipts, leaseId: leaseId);
              },
            ),
          ],
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final receipt in receipts)
          ReceiptListTile(receipt: receipt, leaseId: leaseId),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('btn_see_all_receipts'),
            onPressed: () => context.go('/leases/$leaseId/receipts'),
            icon: const Icon(Icons.list_alt_outlined, size: 18),
            label: const Text('Voir toutes les quittances'),
          ),
        ),
      ],
    );
  }
}

class _EmptyReceiptsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Aucune quittance générée.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
