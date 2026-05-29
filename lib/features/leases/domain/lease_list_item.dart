import 'lease.dart';

/// Modèle composé pour l'affichage de la liste des baux.
///
/// Résultat d'une jointure PostgREST :
/// ```
/// select('*, property:properties(id, name), tenant:tenants(id, first_name, last_name)')
/// ```
///
/// Non-freezed — sérialisation manuelle depuis le JSON imbriqué.
/// Pas de logique métier ici — juste la projection d'affichage.
class LeaseListItem {
  const LeaseListItem({
    required this.lease,
    required this.propertyName,
    required this.tenantDisplayName,
  });

  /// Le bail complet (tous les champs scalaires).
  final Lease lease;

  /// Nom du bien immobilier (de `properties.name`).
  ///
  /// Placeholder si le bien a été archivé entre-temps (RLS filtre `deleted_at IS NULL`
  /// sur la jointure → renvoi `null`).
  final String propertyName;

  /// Nom complet du locataire (`first_name + last_name`).
  ///
  /// Placeholder si le locataire a été archivé entre-temps.
  final String tenantDisplayName;

  factory LeaseListItem.fromJson(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>?;
    final tenant = json['tenant'] as Map<String, dynamic>?;
    return LeaseListItem(
      lease: Lease.fromJson(json),
      propertyName: property?['name'] as String? ?? '(bien archivé)',
      tenantDisplayName: tenant != null
          ? '${tenant['first_name']} ${tenant['last_name']}'
          : '(locataire archivé)',
    );
  }
}
