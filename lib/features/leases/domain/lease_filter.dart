/// Filtre de la liste des baux.
///
/// Utilisé par le [StateProvider] local à la feature leases
/// et le provider dérivé `filteredLeasesProvider`.
enum LeaseFilter {
  /// Tous les baux (aucun filtre).
  all,

  /// Baux actifs uniquement (status == active, non renouvelables, non en
  /// retard).
  active,

  /// Baux actifs dont la date de fin est dans moins de 60 jours (et non en
  /// retard — `late` prime sur `renewable`, cf. FEAT-028).
  renewable,

  /// Baux actifs en retard de paiement au titre du mois dû courant
  /// (FEAT-028, cf. `lease_lateness.dart`). Priorité d'affichage la plus
  /// haute : un bail en retard n'apparaît jamais dans `active` ni
  /// `renewable`.
  late,

  /// Baux terminés.
  terminated;

  /// Libellé affiché dans l'UI française.
  String get labelFr => switch (this) {
    LeaseFilter.all => 'Tous',
    LeaseFilter.active => 'Actifs',
    LeaseFilter.renewable => 'À renouveler',
    LeaseFilter.late => 'En retard',
    LeaseFilter.terminated => 'Terminés',
  };

  /// Parse la valeur d'un query param `?filter=` (drill-down depuis un KPI
  /// dashboard). Retourne `null` si absent ou inconnu → la page garde le
  /// filtre courant du [StateProvider].
  static LeaseFilter? fromQueryParam(String? raw) {
    if (raw == null) return null;
    for (final f in LeaseFilter.values) {
      if (f.name == raw) return f;
    }
    return null;
  }
}
