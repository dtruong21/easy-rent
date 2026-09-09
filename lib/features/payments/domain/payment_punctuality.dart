import '../../leases/domain/lease_lateness.dart';
import 'payment.dart';

/// Ponctualité factuelle des paiements enregistrés d'un bail.
///
/// Purement dérivé des enregistrements du bailleur (paidAt vs échéance + grâce)
/// — aucun jugement, aucun score subjectif, jamais partagé.
class PaymentPunctuality {
  const PaymentPunctuality({required this.total, required this.onTime});

  final int total;
  final int onTime;

  int get late => total - onTime;
  bool get hasPayments => total > 0;

  /// Taux à l'heure entier — `null` sous 3 paiements (évite un % trompeur).
  int? get onTimePercent =>
      total >= 3 ? ((onTime / total) * 100).round() : null;
}

/// Calcule la ponctualité sur [payments] (soft-deleted ignorés).
/// « à l'heure » = `paidAt` au plus tard `échéance + graceDays`.
PaymentPunctuality computePaymentPunctuality(
  List<Payment> payments, {
  required int paymentDay,
  int graceDays = kDefaultLeaseGraceDays,
}) {
  var total = 0;
  var onTime = 0;
  for (final p in payments) {
    if (p.deletedAt != null) continue;
    total++;
    final due = leaseDueDate(
      paymentDay: paymentDay,
      year: p.periodStart.year,
      month: p.periodStart.month,
    );
    if (!p.paidAt.isAfter(due.add(Duration(days: graceDays)))) onTime++;
  }
  return PaymentPunctuality(total: total, onTime: onTime);
}
