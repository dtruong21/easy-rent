/// Filtre de la liste des locataires.
///
/// Utilisé par le [StateProvider] local à la feature tenants
/// et le provider dérivé `filteredTenantsProvider`.
///
/// Enum nu (FEAT-043 i18n) — aucun libellé FR en dur : le mapping vers un
/// libellé localisé vit dans la couche présentation, voir
/// `lib/features/tenants/presentation/tenant_filter_l10n.dart`.
enum TenantFilter {
  /// Tous les locataires (aucun filtre).
  all,

  /// Locataires avec un bail actif uniquement.
  withActiveLease,

  /// Locataires sans bail actif.
  withoutActiveLease,
}
