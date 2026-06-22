/// Filtre de la liste des baux.
///
/// Utilisé par le [StateProvider] local à la feature leases
/// et le provider dérivé `filteredLeasesProvider`.
enum LeaseFilter {
  /// Tous les baux (aucun filtre).
  all,

  /// Baux actifs uniquement (status == active, non renouvelables).
  active,

  /// Baux actifs dont la date de fin est dans moins de 60 jours.
  renewable,

  /// Baux terminés.
  terminated;

  /// Libellé affiché dans l'UI française.
  String get labelFr => switch (this) {
    LeaseFilter.all => 'Tous',
    LeaseFilter.active => 'Actifs',
    LeaseFilter.renewable => 'À renouveler',
    LeaseFilter.terminated => 'Terminés',
  };
}
