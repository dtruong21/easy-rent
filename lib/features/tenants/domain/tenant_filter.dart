/// Filtre de la liste des locataires.
///
/// Utilisé par le [StateProvider] local à la feature tenants
/// et le provider dérivé `filteredTenantsProvider`.
enum TenantFilter {
  /// Tous les locataires (aucun filtre).
  all,

  /// Locataires avec un bail actif uniquement.
  withActiveLease,

  /// Locataires sans bail actif.
  withoutActiveLease;

  /// Libellé affiché dans l'UI française.
  String get labelFr => switch (this) {
    TenantFilter.all => 'Tous',
    TenantFilter.withActiveLease => 'Actifs',
    TenantFilter.withoutActiveLease => 'Sans bail',
  };
}
