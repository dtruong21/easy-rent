import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/theme/property_color.dart';
import '../../properties/presentation/widgets/property_color_dot.dart';
import '../application/lease_receipts_provider.dart';
import '../domain/receipt.dart';
import 'widgets/receipt_status_mapper.dart';

final _log = Logger('ReceiptsListSection');

/// Section "Quittances émises" à intégrer dans [LeaseDetailPage].
///
/// N'affiche plus la liste embarquée des quittances (retour utilisateur
/// 2026-08-11 : zone trop étroite pour une timeline, même limitée à 3
/// éléments) mais une ligne de synthèse compacte et cliquable — nombre de
/// quittances émises + période de la plus récente — qui ouvre l'écran
/// complet `/leases/:id/receipts`. C'est désormais [LeaseReceiptsPage] qui
/// porte seule la liste, ses filtres et le partage.
class ReceiptsListSection extends ConsumerWidget {
  const ReceiptsListSection({
    super.key,
    required this.leaseId,
    this.propertyColorKey,
  });

  final String leaseId;

  /// Couleur d'identité du bien lié — déjà résolue par l'appelant
  /// (`LeaseDetailPage`, qui charge déjà le bien pour d'autres besoins :
  /// zéro lecture supplémentaire).
  final PropertyColorKey? propertyColorKey;

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
            Row(
              children: [
                if (propertyColorKey != null) ...[
                  PropertyColorDot(colorKey: propertyColorKey!),
                  const SizedBox(width: 8),
                ],
                Text(
                  l10n.receiptsSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            asyncReceipts.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) {
                _log.warning('Erreur chargement quittances', e);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.receiptsSectionErrorMessage,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                );
              },
              data: (receipts) {
                if (receipts.isEmpty) {
                  return const _EmptyReceiptsHint();
                }
                return _ReceiptsSummaryEntry(
                  leaseId: leaseId,
                  receipts: receipts,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne de synthèse cliquable — remplace l'ancienne timeline embarquée.
///
/// Affiche le nombre de quittances émises et la période de la plus récente,
/// pour que le bailleur voie l'information sans avoir à cliquer. Un tap
/// n'importe où sur la ligne ouvre `/leases/:id/receipts`.
///
/// [receipts] est trié `period_start DESC` par [LeaseReceiptsNotifier] (voir
/// `lease_receipts_provider.dart`) : [receipts.first] est donc toujours la
/// quittance la plus récente. Le compte inclut les quittances annulées, par
/// cohérence avec [LeaseContextBanner] (`totalReceipts` sur la page complète)
/// — une quittance annulée reste une quittance émise, juste plus valide.
class _ReceiptsSummaryEntry extends StatelessWidget {
  const _ReceiptsSummaryEntry({required this.leaseId, required this.receipts});

  final String leaseId;
  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lastPeriodLabel = receiptPeriodMonthYear(
      receipts.first,
      l10n.localeName,
    );

    return ListTile(
      key: const Key('tile_receipts_summary'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(l10n.receiptsSectionSummaryCount(receipts.length)),
      subtitle: Text(l10n.receiptsSectionSummaryLastLabel(lastPeriodLabel)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/leases/$leaseId/receipts'),
    );
  }
}

class _EmptyReceiptsHint extends StatelessWidget {
  const _EmptyReceiptsHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
