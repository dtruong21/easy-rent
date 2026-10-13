import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../payments/application/lease_payments_provider.dart';
import '../../../payments/domain/payment_punctuality.dart';
import '../../../payments/presentation/widgets/payment_punctuality_indicator.dart';
import '../../application/tenant_leases_provider.dart';

/// Indicateur factuel de ponctualité de paiement agrégé sur l'ensemble des
/// baux d'UN locataire (son propre historique — jamais un comparatif entre
/// locataires). Somme la ponctualité par bail et réutilise la présentation de
/// [PaymentPunctualityView]. Donnée privée, jamais partagée.
class TenantPunctualityIndicator extends ConsumerWidget {
  const TenantPunctualityIndicator({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leases = ref.watch(tenantLeasesProvider(tenantId)).valueOrNull;
    if (leases == null) return const SizedBox.shrink();

    final parts = <PaymentPunctuality>[];
    for (final lease in leases) {
      final leaseId = lease['id'] as String?;
      final paymentDay = lease['payment_day'] as int?;
      if (leaseId == null || paymentDay == null) continue;
      final payments = ref.watch(leasePaymentsProvider(leaseId)).valueOrNull;
      // Un bail encore en chargement → on n'affiche pas de valeur partielle.
      if (payments == null) return const SizedBox.shrink();
      parts.add(computePaymentPunctuality(payments, paymentDay: paymentDay));
    }

    final k = combinePaymentPunctuality(parts);
    if (!k.hasPayments) return const SizedBox.shrink();
    return PaymentPunctualityView(k: k);
  }
}
