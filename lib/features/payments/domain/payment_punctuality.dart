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
    // Normalisation date-civile-LOCALE avant de lire année/mois et de comparer :
    // `periodStart`/`paidAt` relus depuis Firestore sont des instants UTC
    // (`.toUtc().toIso8601String()` à l'écriture). Sans `leaseLocalDate`, le
    // mois lu est décalé d'un cran à l'est d'UTC (ex. « 01/08 » France stocké
    // 2026-07-31T22:00Z → mois=juillet) → échéance un mois trop tôt → faux
    // retards. Même pattern que `isLeaseLate` et `FrenchDate.format`.
    final periodStart = leaseLocalDate(p.periodStart);
    final due = leaseDueDate(
      paymentDay: paymentDay,
      year: periodStart.year,
      month: periodStart.month,
    );
    final paidAt = leaseLocalDate(p.paidAt);
    if (!paidAt.isAfter(due.add(Duration(days: graceDays)))) onTime++;
  }
  return PaymentPunctuality(total: total, onTime: onTime);
}

/// Combine plusieurs [PaymentPunctuality] en un seul (somme additive).
///
/// Utilisé pour agréger la ponctualité d'un locataire sur l'ensemble de ses
/// baux — jamais entre locataires. Les getters dérivés (`late`,
/// `onTimePercent` avec son seuil de 3) s'appliquent au total combiné.
PaymentPunctuality combinePaymentPunctuality(
  Iterable<PaymentPunctuality> parts,
) {
  var total = 0;
  var onTime = 0;
  for (final p in parts) {
    total += p.total;
    onTime += p.onTime;
  }
  return PaymentPunctuality(total: total, onTime: onTime);
}
