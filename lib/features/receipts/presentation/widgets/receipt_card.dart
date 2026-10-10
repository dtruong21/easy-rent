import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/ui/cards/summary_card.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../application/void_receipt_controller.dart';
import '../open_receipt_pdf.dart';
import '../../domain/receipt.dart';
import '../../domain/receipt_action_error.dart';
import 'receipt_action_error_l10n.dart';
import 'receipt_status_mapper.dart';
import 'share_receipt_button.dart';
import 'void_receipt_dialog.dart';

/// Carte d'une quittance dans les listes (Cards + Timeline) — adaptateur
/// [SummaryCard] (spec 2026-09-29). Chiffre clé : montant total CC
/// (`receipt.totalEuros`) + légende « loyer + charges ». Statut : pastille
/// quittance. Action rapide : [ShareReceiptButton] existant. Menu ⋮ :
/// Ouvrir le PDF · Annuler (masqué pendant l'annulation en cours, absent si
/// déjà annulée).
///
/// Tap sur la carte → ouvre le PDF directement (inchangé).
class ReceiptCard extends ConsumerWidget {
  const ReceiptCard({
    super.key,
    required this.receipt,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
    this.propertyColorKey,
  });

  final Receipt receipt;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

  /// Couleur d'identité du bien lié — déjà résolue par l'appelant (le bien
  /// est déjà chargé une seule fois au niveau de la page, cf.
  /// `LeaseReceiptsPage` / `LeaseContextBanner`), jamais une requête par
  /// quittance.
  final PropertyColorKey? propertyColorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final pillData = receiptStatusPill(context, receipt);
    final periodLabel = receiptPeriodMonthYear(receipt, l10n.localeName);
    final secondary = receiptSecondaryLine(context, receipt);
    final isVoiding =
        ref.watch(voidReceiptControllerProvider(receipt.id))
            is VoidReceiptSubmitting;

    _listenVoidState(context, ref, theme);

    String? meta;
    if (receipt.isStale && !receipt.isVoided) {
      meta = l10n.receiptsCardStaleWarning;
    } else if (receipt.isVoided && receipt.voidedReason != null) {
      meta = l10n.receiptsTimelineVoidReasonPrefix(receipt.voidedReason!);
    }

    return SummaryCard(
      key: Key('receipt_card_${receipt.id}'),
      onTap: () => _openPdf(context, ref),
      accentColor: propertyColorKey?.resolveColor(context),
      semanticLabel: l10n.receiptsCardSemanticLabel(
        periodLabel,
        receipt.totalEuros,
      ),
      title: periodLabel,
      subtitle: secondary,
      keyFigure: SummaryKeyFigure(
        value: receipt.totalEuros,
        caption: l10n.receiptsCardTotalCaption,
      ),
      status: StatusPill(
        tone: pillData.tone,
        label: pillData.label,
        icon: pillData.icon,
        size: StatusPillSize.sm,
      ),
      meta: meta,
      quickAction: ShareReceiptButton(
        receipt: receipt,
        leaseId: leaseId,
        tenantEmail: tenantEmail,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
        landlordFullName: landlordFullName,
      ),
      menuKey: Key('receipt_menu_${receipt.id}'),
      menuItems: [
        SummaryMenuItem(
          key: Key('btn_pdf_card_${receipt.id}'),
          label: l10n.receiptsOpenPdfLabel,
          onSelected: () => _openPdf(context, ref),
        ),
        if (!receipt.isVoided && !isVoiding)
          SummaryMenuItem(
            key: Key('btn_void_card_${receipt.id}'),
            label: l10n.receiptsVoidTooltip,
            destructive: true,
            onSelected: () => _showVoidDialog(context, ref),
          ),
      ],
    );
  }

  void _listenVoidState(BuildContext context, WidgetRef ref, ThemeData theme) {
    ref.listen<VoidReceiptState>(voidReceiptControllerProvider(receipt.id), (
      _,
      next,
    ) {
      if (!context.mounted) return;
      if (next is VoidReceiptSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.receiptsVoidSuccessSnackbar),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider(receipt.id).notifier).reset();
      } else if (next is VoidReceiptError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ReceiptActionError.fromCode(next.message).message(context),
            ),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider(receipt.id).notifier).reset();
      }
    });
  }

  Future<void> _openPdf(BuildContext context, WidgetRef ref) =>
      openReceiptPdf(context, ref, receipt.id);

  Future<void> _showVoidDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Consumer(
        builder: (context, ref, _) {
          final isVoiding =
              ref.watch(voidReceiptControllerProvider(receipt.id))
                  is VoidReceiptSubmitting;
          return VoidReceiptDialog(
            isSubmitting: isVoiding,
            onConfirm: (reason) {
              Navigator.of(dialogCtx).pop();
              ref
                  .read(voidReceiptControllerProvider(receipt.id).notifier)
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
