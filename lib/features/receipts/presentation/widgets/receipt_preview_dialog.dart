import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/document_type.dart';
import '../../domain/receipt_generation_result.dart';
import 'document_type_l10n.dart';

/// Dialog affiché après la génération réussie d'une quittance.
///
/// Affiche un récapitulatif (période, montant, type de document) et propose
/// d'ouvrir le PDF dans un nouvel onglet du navigateur.
///
/// Note : on ne fait pas de preview embedded — un nouvel onglet est plus simple
/// et plus pratique sur Flutter Web.
class ReceiptPreviewDialog extends StatelessWidget {
  const ReceiptPreviewDialog({super.key, required this.result});

  final ReceiptGenerationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isQuittance = result.documentType == DocumentType.quittance;
    final title = isQuittance
        ? l10n.receiptsPreviewTitleQuittance
        : l10n.receiptsPreviewTitleRecu;
    final periodLabel =
        '${FrenchDate.format(result.periodStart)} – ${FrenchDate.format(result.periodEnd)}';
    final totalLabel = MoneyFormat.formatEurosFromCents(result.totalCents);

    return AlertDialog(
      key: const Key('dialog_receipt_preview'),
      title: Row(
        children: [
          Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: l10n.receiptsPreviewTypeLabel,
            value: result.documentType.localizedLabel(context),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: l10n.receiptsPreviewPeriodLabel, value: periodLabel),
          const SizedBox(height: 8),
          _InfoRow(label: l10n.receiptsPreviewTotalLabel, value: totalLabel),
          if (!isQuittance) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.receiptsPreviewRecuDisclaimer,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('btn_receipt_preview_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
        FilledButton.icon(
          key: const Key('btn_receipt_preview_open'),
          onPressed: () => _openPdf(context),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l10n.receiptsOpenPdfLabel),
        ),
      ],
    );
  }

  Future<void> _openPdf(BuildContext context) async {
    final uri = Uri.parse(result.pdfUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.receiptsErrorOpenPdfBrowser)),
        );
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            // FEAT-043 : [label] porte déjà le séparateur deux-points localisé
            // (« Type : » en FR, « Type: » en EN — convention typographique
            // différente selon la locale), plus besoin de le concaténer ici.
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
