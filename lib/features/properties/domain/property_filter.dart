/// Filtre de la liste des biens immobiliers.
///
/// Utilisé par le [StateProvider] local à la feature properties
/// et le provider dérivé `filteredPropertiesProvider`.
enum PropertyFilter {
  /// Tous les biens (aucun filtre).
  all,

  /// Biens occupés uniquement (bail actif existant).
  occupied,

  /// Biens vacants uniquement (aucun bail actif).
  vacant;

  /// Libellé affiché dans l'UI française.
  String get labelFr => switch (this) {
    PropertyFilter.all => 'Tous',
    PropertyFilter.occupied => 'Loués',
    PropertyFilter.vacant => 'Vacants',
  };
}
