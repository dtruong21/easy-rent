/// Filtre de la liste des biens immobiliers.
///
/// Utilisé par le [StateProvider] local à la feature properties
/// et le provider dérivé `filteredPropertiesProvider`.
///
/// FEAT-043 (i18n) : cet enum ne porte plus de libellé FR en dur (ancien
/// getter `labelFr`, retiré — zéro référence restante). Le mapping enum →
/// libellé localisé vit dans la couche présentation : voir
/// `PropertyFilterL10n`
/// (`lib/features/properties/presentation/widgets/property_filter_l10n.dart`).
enum PropertyFilter {
  /// Tous les biens (aucun filtre).
  all,

  /// Biens occupés uniquement (bail actif existant).
  occupied,

  /// Biens vacants uniquement (aucun bail actif).
  vacant,
}
