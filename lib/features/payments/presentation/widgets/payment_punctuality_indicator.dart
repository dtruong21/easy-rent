import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../application/lease_payments_provider.dart';
import '../../domain/payment_punctuality.dart';

/// Indicateur factuel de ponctualité de paiement, en tête de la section
/// Paiements d'un bail. Responsive : ligne complète en large, pill compact
/// (< 600 px), détail au tap. Donnée privée, jamais partagée.
class PaymentPunctualityIndicator extends ConsumerWidget {
  const PaymentPunctualityIndicator({
    super.key,
    required this.leaseId,
    required this.paymentDay,
  });

  final String leaseId;
  final int paymentDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(leasePaymentsProvider(leaseId)).valueOrNull;
    if (payments == null) return const SizedBox.shrink();

    final k = computePaymentPunctuality(payments, paymentDay: paymentDay);
    if (!k.hasPayments) {
      return const SizedBox.shrink();
    }

    return PaymentPunctualityView(k: k);
  }
}

/// Présentation d'un [PaymentPunctuality] : ligne/pill responsive + feuille
/// de détail au tap. Réutilisable par [PaymentPunctualityIndicator] (par bail)
/// et par l'indicateur agrégé (par locataire).
class PaymentPunctualityView extends StatelessWidget {
  const PaymentPunctualityView({super.key, required this.k});

  final PaymentPunctuality k;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final l10n = context.l10n;

    final tone = k.late > 0 ? colors.warning : colors.success;

    Widget content;
    if (context.isMobile) {
      final label = k.late > 0
          ? '${k.onTime}/${k.total} · ${l10n.paymentsPunctualityLateShort(k.late)}'
          : '${k.onTime}/${k.total}';
      content = Container(
        key: const Key('payment_punctuality_pill'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              k.late > 0 ? Icons.schedule : Icons.check_circle_outline,
              size: 14,
              color: tone.onSurface,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final parts = <String>[
        l10n.paymentsPunctualityOnTime(k.onTime, k.total),
        if (k.late > 0) l10n.paymentsPunctualityLate(k.late),
        if (k.onTimePercent != null) '${k.onTimePercent} %',
      ];
      content = Row(
        key: const Key('payment_punctuality_line'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            k.late > 0 ? Icons.schedule : Icons.check_circle_outline,
            size: 16,
            color: tone.solid,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              parts.join(' · '),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      key: const Key('payment_punctuality_tap'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showDetail(context, k),
      child: content,
    );
  }

  void _showDetail(BuildContext context, PaymentPunctuality k) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colors = theme.extension<AppColors>()!;
        final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
        return Padding(
          key: const Key('payment_punctuality_sheet'),
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.paymentsPunctualitySheetTitle,
                style: theme.textTheme.titleMedium,
              ),
              SizedBox(height: spacing.xs),
              Text(
                l10n.paymentsPunctualityMethod,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: spacing.md),
              Row(
                children: [
                  Expanded(
                    child: _DetailTile(
                      label: l10n.paymentsPunctualityOnTimeLabel,
                      value: '${k.onTime}/${k.total}',
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: _DetailTile(
                      label: l10n.paymentsPunctualityLateLabel,
                      value: k.late.toString(),
                      color: colors.warning.solid,
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              Text(
                l10n.paymentsPunctualityPrivacy,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
