import '../../leases/domain/lease.dart';
import 'payment.dart';

/// Période proposée par défaut pour un NOUVEAU paiement (recette iOS, #197 :
/// les dates de période n'étaient pas préremplies).
///
/// Règle, fonction pure (aucune E/S, [now] injectable) :
/// - **Des paiements existent** : la période suit le dernier paiement — du
///   lendemain de sa fin à la fin de ce mois-là (fin au 31 mars → avril
///   entier ; fin au 14 avril → du 15 au 30 avril).
/// - **Aucun paiement** : le mois courant, ou le mois de démarrage du bail
///   s'il démarre plus tard ; le premier mois commence au jour de démarrage.
/// - La fin est bornée par la fin du bail. `null` si la période proposée
///   commencerait après la fin du bail (rien à proposer).
///
/// Les dates sont des jours calendaires locaux (minuit), comme celles du
/// sélecteur de date du formulaire.
({DateTime start, DateTime end})? suggestedPaymentPeriod({
  required Lease lease,
  required List<Payment> payments,
  required DateTime now,
}) {
  final leaseStart = _day(lease.startDate);

  DateTime start;
  if (payments.isNotEmpty) {
    final lastEnd = payments
        .map((p) => _day(p.periodEnd))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    start = DateTime(lastEnd.year, lastEnd.month, lastEnd.day + 1);
  } else {
    start = DateTime(now.year, now.month);
  }
  if (start.isBefore(leaseStart)) {
    // Bail qui démarre plus tard (ou en cours de mois) : 1er mois dû = à
    // partir du jour de démarrage.
    start = leaseStart;
  }

  var end = DateTime(start.year, start.month + 1, 0); // dernier jour du mois
  final leaseEnd = lease.endDate == null ? null : _day(lease.endDate!);
  if (leaseEnd != null && leaseEnd.isBefore(end)) end = leaseEnd;
  if (end.isBefore(start)) return null;

  return (start: start, end: end);
}

/// Jour calendaire local, à minuit (les dates Firestore reviennent en UTC).
DateTime _day(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}
