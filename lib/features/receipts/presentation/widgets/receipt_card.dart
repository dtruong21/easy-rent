import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ui/cards/entity_card.dart';
import '../../../../core/ui/cards/entity_card_header.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../application/void_receipt_controller.dart';
import '../../data/receipts_repository.dart';
import '../../domain/receipt.dart';
import 'receipt_status_mapper.dart';
import 'share_receipt_button.dart';
import 'void_receipt_dialog.dart';

final _log = Logger('ReceiptCard');

/// Carte v2 représentant une quittance dans la vue Cards.
///
/// Utilise [EntityCard] pour un layout cohérent avec les autres entités.
/// - Header : période (mois année) + [StatusPill] statut.
/// - Body : montant CC, avertissement périmée/annulée.
/// - Footer : "PDF" + [ShareReceiptButton] + bouton "Annuler".
///
/// Tap sur la carte → ouvre le PDF directement.
class ReceiptCard extends ConsumerWidget {
  const ReceiptCard({
    super.key,
    required this.receipt,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
  });

  final Receipt receipt;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pillData = receiptStatusPill(receipt);
    final periodLabel = receiptPeriodMonthYear(receipt);
    final secondary = receiptSecondaryLine(receipt);

    _listenVoidState(context, ref, theme);

    return EntityCard(
      key: Key('receipt_card_${receipt.id}'),
      onTap: () => _openPdf(context, ref),
      semanticLabel: 'Quittance $periodLabel — ${receipt.totalEuros}',
      header: EntityCardHeader(
        title: Text(
          periodLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
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
        subtitle: Text(
          secondary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _ReceiptCardBody(receipt: receipt),
      footer: _ReceiptCardFooter(
        receipt: receipt,
        leaseId: leaseId,
        tenantEmail: tenantEmail,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
        landlordFullName: landlordFullName,
        onOpenPdf: () => _openPdf(context, ref),
        onVoid: () => _showVoidDialog(context, ref),
      ),
    );
  }

  void _listenVoidState(BuildContext context, WidgetRef ref, ThemeData theme) {
    ref.listen<VoidReceiptState>(voidReceiptControllerProvider, (_, next) {
      if (!context.mounted) return;
      if (next is VoidReceiptSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quittance annulée'),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      } else if (next is VoidReceiptError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      }
    });
  }

  Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final url = await repo.signedUrl(receipt.id);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Impossible d'ouvrir le PDF. Vérifiez votre navigateur.",
              ),
            ),
          );
        }
      }
    } catch (e, st) {
      _log.warning('Erreur ouverture PDF', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Impossible de générer le lien de téléchargement.',
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  Future<void> _showVoidDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Consumer(
        builder: (context, ref, _) {
          final isVoiding =
              ref.watch(voidReceiptControllerProvider) is VoidReceiptSubmitting;
          return VoidReceiptDialog(
            isSubmitting: isVoiding,
            onConfirm: (reason) {
              Navigator.of(dialogCtx).pop();
              ref
                  .read(voidReceiptControllerProvider.notifier)
                  .voidReceipt(
                    receiptId: receipt.id,
                    reason: reason,
                    leaseId: leaseId,
                  );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body : montant + avertissements
// ---------------------------------------------------------------------------

class _ReceiptCardBody extends StatelessWidget {
  const _ReceiptCardBody({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReceiptCardRow(
          icon: Icons.euro_outlined,
          text: '${receipt.totalEuros} CC',
          color: theme.colorScheme.onSurfaceVariant,
        ),
        if (receipt.isStale && !receipt.isVoided) ...[
          const SizedBox(height: 4),
          _ReceiptCardRow(
            icon: Icons.warning_amber_outlined,
            text: 'Quittance périmée',
            color: theme.colorScheme.error,
          ),
        ],
        if (receipt.isVoided && receipt.voidedReason != null) ...[
          const SizedBox(height: 4),
          _ReceiptCardRow(
            icon: Icons.info_outline,
            text: receipt.voidedReason!,
            color: theme.colorScheme.error,
          ),
        ],
      ],
    );
  }
}

class _ReceiptCardRow extends StatelessWidget {
  const _ReceiptCardRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Footer : PDF + Partager + Annuler
// ---------------------------------------------------------------------------

class _ReceiptCardFooter extends ConsumerWidget {
  const _ReceiptCardFooter({
    required this.receipt,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
    required this.onOpenPdf,
    required this.onVoid,
  });

  final Receipt receipt;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;
  final VoidCallback onOpenPdf;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final voidState = ref.watch(voidReceiptControllerProvider);
    final isVoiding = voidState is VoidReceiptSubmitting;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          key: Key('btn_pdf_card_${receipt.id}'),
          onPressed: onOpenPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: const Text('PDF'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: theme.textTheme.labelSmall,
          ),
        ),
        ShareReceiptButton(
          receipt: receipt,
          leaseId: leaseId,
          tenantEmail: tenantEmail,
          tenantFirstName: tenantFirstName,
          propertyAddress: propertyAddress,
          landlordFullName: landlordFullName,
        ),
        if (!receipt.isVoided)
          IconButton(
            key: Key('btn_void_card_${receipt.id}'),
            icon: Icon(
              Icons.cancel_outlined,
              color: theme.colorScheme.error,
              size: 20,
            ),
            tooltip: 'Annuler la quittance',
            onPressed: isVoiding ? null : onVoid,
            style: IconButton.styleFrom(
              minimumSize: const Size(32, 32),
              padding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
