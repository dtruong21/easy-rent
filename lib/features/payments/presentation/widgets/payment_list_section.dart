import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../../../core/utils/money_format.dart';
import '../../../leases/application/lease_detail_provider.dart';
import '../../../leases/domain/lease.dart';
import '../../../properties/presentation/widgets/property_color_dot.dart';
import '../../application/lease_payments_provider.dart';
import '../../application/payment_form_controller.dart';
import '../../domain/payment.dart';
import 'payment_list_tile.dart';

final _log = Logger('PaymentListSection');

/// Section "Paiements" à intégrer dans [LeaseDetailPage].
///
/// Remplace [_PaymentsPlaceholder] (FEAT-005) après FEAT-006.
///
/// Affiche la liste des paiements triés par [period_start DESC].
/// Bouton "Ajouter paiement" désactivé si bail clôturé
/// (status ∈ {terminated, archived}).
class PaymentListSection extends ConsumerWidget {
  const PaymentListSection({
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
    final asyncLease = ref.watch(leaseDetailProvider(leaseId));
    final asyncPayments = ref.watch(leasePaymentsProvider(leaseId));

    return asyncLease.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (lease) => _PaymentListContent(
        lease: lease,
        asyncPayments: asyncPayments,
        leaseId: leaseId,
        propertyColorKey: propertyColorKey,
      ),
    );
  }
}

class _PaymentListContent extends ConsumerWidget {
  const _PaymentListContent({
    required this.lease,
    required this.asyncPayments,
    required this.leaseId,
    this.propertyColorKey,
  });

  final Lease lease;
  final AsyncValue<List<Payment>> asyncPayments;
  final String leaseId;
  final PropertyColorKey? propertyColorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isClosed = !lease.isActive;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête avec titre et bouton ajouter
            Row(
              children: [
                if (propertyColorKey != null) ...[
                  PropertyColorDot(colorKey: propertyColorKey!),
                  const SizedBox(width: 8),
                ],
                Text(
                  context.l10n.paymentsSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Tooltip(
                  message: isClosed
                      ? context.l10n.paymentsAddDisabledTooltip
                      : context.l10n.paymentsAddTooltip,
                  child: FilledButton.icon(
                    key: const Key('btn_add_payment'),
                    onPressed: isClosed
                        ? null
                        : () => context.push('/leases/$leaseId/payments/new'),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.l10n.paymentsAddButton),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Corps : liste ou états de chargement/erreur/vide
            asyncPayments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) {
                _log.warning('Erreur chargement paiements', e);
                return Text(
                  context.l10n.paymentsListErrorLoading,
                  style: TextStyle(color: theme.colorScheme.error),
                );
              },
              data: (payments) {
                if (payments.isEmpty) {
                  return _EmptyPaymentsHint(
                    isClosed: isClosed,
                    leaseId: leaseId,
                  );
                }
                return Column(
                  children: [
                    for (final payment in payments)
                      PaymentListTile(
                        payment: payment,
                        leaseId: leaseId,
                        onEdit: () => context.push(
                          '/leases/$leaseId/payments/${payment.id}/edit',
                        ),
                        onArchive: () =>
                            _archivePayment(context, ref, payment.id),
                      ),
                    const Divider(),
                    _TotalRow(payments: payments),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _archivePayment(
    BuildContext context,
    WidgetRef ref,
    String paymentId,
  ) async {
    await ref
        .read(paymentFormControllerProvider.notifier)
        .archive(paymentId: paymentId, leaseId: leaseId);
    if (!context.mounted) return;
    final state = ref.read(paymentFormControllerProvider);
    final errorMsg = state.maybeWhen(error: (msg) => msg, orElse: () => null);
    if (errorMsg != null) {
      _log.warning('archive payment error: $errorMsg');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.paymentsArchiveSuccessSnackbar),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
    }
  }
}

/// Ligne du total des paiements.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.payments});

  final List<Payment> payments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCents = payments.fold<int>(
      0,
      (sum, p) => sum + p.totalAmountCents,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.l10n.paymentsTotalCollectedLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            MoneyFormat.formatEurosFromCents(totalCents),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hint affiché quand il n'y a aucun paiement.
class _EmptyPaymentsHint extends StatelessWidget {
  const _EmptyPaymentsHint({required this.isClosed, required this.leaseId});

  final bool isClosed;
  final String leaseId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        isClosed
            ? context.l10n.paymentsEmptyClosedMessage
            : context.l10n.paymentsEmptyMessage,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
