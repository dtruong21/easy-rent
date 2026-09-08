import 'lease.dart';

/// `true` si le bail a une date de fin dans moins de 60 jours.
///
/// Extrait de `leases_filter_provider` pour partager le seuil unique entre
/// l'écran Baux (filtre « renouvelable ») et le dashboard (« baux finissant »).
/// Ne teste PAS le statut ni le retard : la priorité FEAT-028 (late > renewable
/// > active) reste gérée par l'appelant.
bool isLeaseRenewable(Lease lease, DateTime now) {
  final end = lease.endDate;
  if (end == null) return false;
  return end.difference(now).inDays < 60;
}
