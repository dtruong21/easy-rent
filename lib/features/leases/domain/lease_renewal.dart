import 'lease.dart';

/// Fenêtre de renouvellement : un bail est « à renouveler » quand sa date de
/// fin tombe dans les [kLeaseRenewalWindowDays] prochains jours.
///
/// Seuil unique partagé par tous les consommateurs de la notion « à renouveler »
/// pour qu'ils ne divergent jamais :
/// - le filtre `renewable` de la liste des baux ;
/// - le panneau d'actions « baux finissant » du dashboard ;
/// - le KPI « Baux à renouveler » (`fetchRenouvellements`).
const int kLeaseRenewalWindowDays = 60;

/// `true` si le bail a une date de fin dans moins de [kLeaseRenewalWindowDays]
/// jours (borne stricte).
///
/// Extrait de `leases_filter_provider` pour partager le seuil unique entre
/// l'écran Baux (filtre « renouvelable ») et le dashboard (« baux finissant »).
/// Ne teste PAS le statut ni le retard : la priorité FEAT-028 (late > renewable
/// > active) reste gérée par l'appelant.
bool isLeaseRenewable(Lease lease, DateTime now) {
  final end = lease.endDate;
  if (end == null) return false;
  return end.difference(now).inDays < kLeaseRenewalWindowDays;
}
