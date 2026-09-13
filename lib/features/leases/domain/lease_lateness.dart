/// Détection de retard de paiement sur un bail (FEAT-028).
///
/// Fonction pure, testable sans dépendance Firestore : reçoit un [Lease] et
/// les [Payment] déjà chargés, retourne un booléen. Aucune E/S ici — le
/// chargement des paiements par bail est à la charge de l'appelant
/// (`DashboardRepository.fetchRetards`, `LeaseRepository.listForDisplay`).
///
/// ## Règle métier (décisions produit tranchées, 2026-07-04)
///
/// - Délai de grâce : 5 jours calendaires après l'échéance (valeur par
///   défaut de [graceDays], non paramétrable par bail dans cette itération).
/// - Pas de proratisation du 1er mois : la 1ʳᵉ échéance due est le premier
///   mois calendaire (à partir du mois de démarrage du bail inclus) dont
///   l'échéance tombe le jour de démarrage du bail ou après. Un bail qui
///   démarre après le jour d'échéance du mois courant saute donc au mois
///   suivant.
/// - Échéance d'un mois `M` = `min(paymentDay, dernierJour(M))` — clamp pour
///   les mois courts (ex. `paymentDay=31` en février → 28 ou 29).
/// - Couverture : un paiement `P` couvre le mois `M` s'il y a recouvrement
///   d'intervalle — `P.periodStart <= dernierJour(M) && P.periodEnd >=
///   premierJour(M)`. Un seul paiement qui recouvre suffit (pas d'union de
///   plusieurs paiements partiels nécessaire — le montant n'est jamais
///   vérifié, hors scope MVP).
/// - Un bail non actif (`terminated` / `archived`) n'est jamais en retard.
library;

import '../../payments/domain/payment.dart';
import 'lease.dart';
import 'lease_status.dart';

/// Délai de grâce par défaut, en jours calendaires, appliqué après
/// l'échéance avant qu'un bail soit considéré en retard.
const int kDefaultLeaseGraceDays = 5;

/// Retourne `true` si [lease] a un loyer impayé au titre de son « mois dû
/// courant » (cf. doc de fichier pour la définition complète).
///
/// [now] est injectable pour les tests (évite la dépendance à
/// `DateTime.now()`). [graceDays] est injectable pour les tests de bornes
/// mais reste une constante applicative en production
/// ([kDefaultLeaseGraceDays]).
bool isLeaseLate({
  required Lease lease,
  required Iterable<Payment> payments,
  required DateTime now,
  int graceDays = kDefaultLeaseGraceDays,
}) {
  // Un bail non actif (terminated/archived) n'est jamais en retard, quelle
  // que soit l'historique de paiement.
  if (lease.status != LeaseStatus.active) {
    return false;
  }

  // Tronque à la partie date CIVILE LOCALE (cf. doc `leaseLocalDate` pour le
  // détail du bug de fuseau que cette conversion neutralise — `startDate`
  // relu depuis Firestore est un DateTime UTC, décalé d'un jour par rapport
  // au calendrier local selon l'heure de la journée).
  final dueMonth = _currentDueMonth(
    startDate: leaseLocalDate(lease.startDate),
    paymentDay: lease.paymentDay,
    now: leaseLocalDate(now),
    graceDays: graceDays,
  );

  // Pas encore de mois dû (bail trop récent, ou 1ʳᵉ échéance encore dans le
  // délai de grâce) → jamais en retard.
  if (dueMonth == null) {
    return false;
  }

  final coveredByAnyPayment = payments.any(
    (p) => _paymentCoversMonth(p, dueMonth),
  );
  return !coveredByAnyPayment;
}

/// Représente un mois calendaire (année + mois, sans jour).
typedef _YearMonth = ({int year, int month});

/// Date d'échéance du mois [month]/[year] pour un jour d'échéance [paymentDay],
/// clampée au dernier jour du mois si celui-ci est plus court. Publique pour
/// être réutilisée (indicateur de ponctualité des paiements).
DateTime leaseDueDate({
  required int paymentDay,
  required int year,
  required int month,
}) {
  final lastDay = _lastDayOfMonth(year, month);
  final day = paymentDay > lastDay ? lastDay : paymentDay;
  return DateTime(year, month, day);
}

/// Calcule le « mois dû courant » : le mois calendaire le plus récent tel
/// que son échéance + [graceDays] est `<= now`, en partant du premier mois
/// éligible (celui dont l'échéance tombe le jour de démarrage du bail ou
/// après — pas de proratisation).
///
/// Retourne `null` si aucun mois n'est encore dû (bail trop récent, ou
/// 1ʳᵉ échéance dans le délai de grâce).
_YearMonth? _currentDueMonth({
  required DateTime startDate,
  required int paymentDay,
  required DateTime now,
  required int graceDays,
}) {
  final firstEligibleMonth = _firstEligibleDueMonth(startDate, paymentDay);

  _YearMonth? lastDueMonth;
  var candidate = firstEligibleMonth;

  // Boucle bornée par `now` : chaque itération avance d'un mois, la
  // condition d'arrêt (échéance + grâce > now) est garantie atteinte car le
  // temps calendaire est monotone. Pas de risque de boucle infinie tant que
  // `now` est une date finie.
  while (true) {
    final dueDate = _dueDateFor(candidate, paymentDay);
    final graceDeadline = dueDate.add(Duration(days: graceDays));
    if (graceDeadline.isAfter(now)) {
      break;
    }
    lastDueMonth = candidate;
    candidate = _nextMonth(candidate);
  }

  return lastDueMonth;
}

/// Premier mois calendaire (à partir du mois de démarrage inclus) dont
/// l'échéance tombe le jour de démarrage du bail ou après.
///
/// Exemple : bail démarrant le 15 mars, `paymentDay=5` → l'échéance de mars
/// (5 mars) est AVANT le 15 mars → on saute à avril (5 avril, qui est bien
/// après le 15 mars par définition puisqu'avril suit mars).
_YearMonth _firstEligibleDueMonth(DateTime startDate, int paymentDay) {
  var candidate = (year: startDate.year, month: startDate.month);
  while (_dueDateFor(candidate, paymentDay).isBefore(startDate)) {
    candidate = _nextMonth(candidate);
  }
  return candidate;
}

/// Date d'échéance du mois [ym] pour un jour d'échéance [paymentDay],
/// clampé au dernier jour du mois si celui-ci est plus court.
DateTime _dueDateFor(_YearMonth ym, int paymentDay) =>
    leaseDueDate(paymentDay: paymentDay, year: ym.year, month: ym.month);

/// Dernier jour du mois [month] de l'année [year] (28-31).
int _lastDayOfMonth(int year, int month) {
  // Jour 0 du mois suivant = dernier jour du mois courant.
  return DateTime(year, month + 1, 0).day;
}

_YearMonth _nextMonth(_YearMonth ym) {
  if (ym.month == 12) {
    return (year: ym.year + 1, month: 1);
  }
  return (year: ym.year, month: ym.month + 1);
}

/// Vrai si [payment] recouvre (au moins partiellement) le mois [month] :
/// `periodStart <= dernierJourDuMois && periodEnd >= premierJourDuMois`.
bool _paymentCoversMonth(Payment payment, _YearMonth month) {
  final firstDay = DateTime(month.year, month.month, 1);
  final lastDay = DateTime(
    month.year,
    month.month,
    _lastDayOfMonth(month.year, month.month),
  );
  final periodStart = leaseLocalDate(payment.periodStart);
  final periodEnd = leaseLocalDate(payment.periodEnd);
  return !periodStart.isAfter(lastDay) && !periodEnd.isBefore(firstDay);
}

/// Tronque une [DateTime] à sa partie date CIVILE LOCALE (ignore l'heure).
///
/// Convertit d'abord en heure locale via [DateTime.toLocal] AVANT de
/// tronquer — exactement le pattern déjà utilisé par
/// `FrenchDate.format`/`frenchMonthYear` (lib/core/utils/french_date.dart).
///
/// Pourquoi c'est indispensable ici : en chaîne de prod, `startDate`,
/// `periodStart` et `periodEnd` sont écrits `.toUtc().toIso8601String()`
/// puis relus par `firestoreDocToSnakeJson`
/// (`Timestamp.toDate().toUtc().toIso8601String()`, cf.
/// `core/firestore_helpers.dart`) — `DateTime.parse` sur cette chaîne
/// suffixée `Z` renvoie un `DateTime` **UTC**. Tronquer directement cet
/// instant UTC (`DateTime(dt.year, dt.month, dt.day)` SANS `.toLocal()`
/// préalable) lit le jour UTC, décalé de −1 jour en France (UTC+1/+2) selon
/// l'heure de la journée — ex. minuit Europe/Paris le 16 juin devient
/// 22h/23h UTC le 15 juin, et le jour lu serait 15 au lieu de 16. Un bail
/// démarrant le 16 juin avec `paymentDay=15` deviendrait alors faussement
/// éligible dès juin (paymentDay <= jour lu) au lieu d'attendre juillet.
/// `.toLocal()` avant troncature neutralise ce décalage en ramenant tout
/// sur le même calendrier civil (Europe/Paris) que celui utilisé à la
/// saisie (date picker local) et par `DateTime.now()`.
/// Public (partagé avec `payment_punctuality.dart`) — même normalisation
/// date-civile-locale requise partout où l'on lit `.year/.month/.day` d'une
/// date relue depuis Firestore (instant UTC).
DateTime leaseLocalDate(DateTime dt) {
  final local = dt.toLocal();
  return DateTime(local.year, local.month, local.day);
}
