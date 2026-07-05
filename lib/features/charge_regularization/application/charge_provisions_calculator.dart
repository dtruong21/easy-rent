/// Calcul des provisions de charges encaissées sur une période de référence
/// (FEAT-029 V1.2 — régularisation annuelle des charges, bail nu).
///
/// Fonction pure, testable sans dépendance Firestore : reçoit une liste de
/// [Payment] déjà chargés (via `PaymentRepository.listForLease`, lecture
/// client existante) et une période de référence, retourne la somme des
/// `chargesAmountCents` des paiements dont la période RECOUVRE (au moins
/// partiellement) la période de référence.
///
/// Piège de fuseau horaire (même pattern que `lease_lateness.dart`,
/// `_dateOnly`) : `periodStart`/`periodEnd` d'un [Payment] relu depuis
/// Firestore sont des `DateTime` UTC (écrits `.toUtc().toIso8601String()`,
/// relus via `firestoreDocToSnakeJson`). Comparer directement ces instants
/// UTC à une période de référence choisie en heure LOCALE (date picker)
/// décale les bornes d'un jour selon l'heure de la journée — un paiement de
/// période "01/01/2025" pourrait sembler démarrer le "31/12/2024" si on ne
/// tronque pas en date civile locale avant de comparer. On applique donc
/// systématiquement `.toLocal()` avant de tronquer à `DateTime(y, m, d)`.
library;

import '../../payments/domain/payment.dart';

/// Somme des `chargesAmountCents` des [payments] dont la période
/// (`periodStart` → `periodEnd`) recouvre, au moins partiellement, la
/// période de référence `[referenceStart, referenceEnd]` (bornes incluses).
///
/// Recouvrement d'intervalle : `payment.periodStart <= referenceEnd &&
/// payment.periodEnd >= referenceStart` — un seul jour de chevauchement
/// suffit à inclure le paiement en totalité (pas de proratisation
/// jour-par-jour, cohérent avec `lease_lateness.dart` et hors scope MVP).
///
/// Les [payments] non filtrés en amont par `leaseId` seront simplement
/// inclus dans la somme s'ils recouvrent la période — l'appelant est
/// responsable de ne fournir que les paiements du bail concerné (résultat de
/// `PaymentRepository.listForLease(leaseId)`).
int sumChargeProvisionsForPeriod({
  required Iterable<Payment> payments,
  required DateTime referenceStart,
  required DateTime referenceEnd,
}) {
  final start = _dateOnly(referenceStart);
  final end = _dateOnly(referenceEnd);

  var total = 0;
  for (final payment in payments) {
    final periodStart = _dateOnly(payment.periodStart);
    final periodEnd = _dateOnly(payment.periodEnd);
    final overlaps = !periodStart.isAfter(end) && !periodEnd.isBefore(start);
    if (overlaps) {
      total += payment.chargesAmountCents;
    }
  }
  return total;
}

/// Tronque une [DateTime] à sa partie date CIVILE LOCALE (ignore l'heure).
///
/// Duplique intentionnellement `_dateOnly` de
/// `lib/features/leases/domain/lease_lateness.dart` — fonction privée dans
/// les deux fichiers, extraction dans un helper partagé jugée non justifiée
/// pour 2 usages (`core/utils/date_bounds.dart` porte des bornes absolues,
/// pas des helpers de troncature ; créer un fichier core dédié pour une
/// fonction de 3 lignes utilisée 2 fois aurait été une sur-ingénierie).
DateTime _dateOnly(DateTime dt) {
  final local = dt.toLocal();
  return DateTime(local.year, local.month, local.day);
}
