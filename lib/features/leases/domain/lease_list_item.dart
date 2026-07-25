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
    this.isLate = false,
  });

  /// Le bail complet (tous les champs scalaires).
  final Lease lease;

  /// Nom du bien immobilier (de `properties.name`).
  ///
  /// Placeholder si le bien a été archivé entre-temps (les Rules filtrent `deletedAt == null`
  /// sur la jointure → renvoi `null`).
  final String propertyName;

  /// Nom complet du locataire (`first_name + last_name`).
  ///
  /// Placeholder si le locataire a été archivé entre-temps.
  final String tenantDisplayName;

  /// Vrai si le bail est en retard de paiement au titre du mois dû courant
  /// (FEAT-028, cf. `lease_lateness.dart::isLeaseLate`).
  ///
  /// Calculé par [LeaseRepository.listForDisplay] à partir des paiements du
  /// bail — toujours `false` pour un bail non actif. Défaut `false` pour ne
  /// pas casser les call sites existants (formulaires, tests) qui ne
  /// connaissent pas cette notion.
  final bool isLate;

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
