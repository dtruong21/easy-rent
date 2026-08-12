import '../../../core/utils/money_format.dart';
import 'property.dart';

/// Modèle composé pour l'affichage de la liste des biens immobiliers.
///
/// Résultat d'une jointure PostgREST :
/// ```
/// select('*, leases:leases!leases_property_id_fkey(
///   id, rent_amount_cents, charges_amount_cents, status, deleted_at,
///   tenant:tenants(id, first_name, last_name))')
/// ```
///
/// Non-freezed — sérialisation manuelle depuis le JSON imbriqué.
/// Pas de logique métier ici — juste la projection d'affichage.
class PropertyListItem {
  const PropertyListItem({
    required this.property,
    this.activeLeaseId,
    this.currentTenantName,
    this.currentRentLabel,
    this.currentRentHcCents,
  });

  /// Le bien immobilier complet (tous les champs scalaires).
  final Property property;

  /// Identifiant du bail actif, ou `null` si vacant.
  final String? activeLeaseId;

  /// Nom complet du locataire en cours, ou `null` si vacant.
  final String? currentTenantName;

  /// Loyer CC formaté FR (ex. "1 200,00 € CC / mois"), ou `null` si vacant.
  final String? currentRentLabel;

  /// Loyer hors charges du bail actif, en centimes bruts — ou `null` si
  /// vacant. Nécessaire aux calculs de rentabilité (`core/finance`), qui
  /// attendent le loyer HC et non le libellé CC formaté.
  final int? currentRentHcCents;

  /// Construit un [PropertyListItem] depuis le JSON brut de PostgREST.
  ///
  /// La clé `leases` contient une liste de baux (jointure 1-N).
  /// On filtre `status='active' AND deleted_at IS NULL` côté client.
  /// Si plusieurs baux actifs existent pour un même bien, on prend le premier
  /// (cas anormal — normalement 1 bail actif max par bien selon convention métier).
  factory PropertyListItem.fromJson(Map<String, dynamic> json) {
    final leasesRaw = json['leases'] as List<dynamic>?;

    Map<String, dynamic>? activeLease;
    if (leasesRaw != null) {
      for (final raw in leasesRaw) {
        final lease = raw as Map<String, dynamic>;
        final status = lease['status'] as String?;
        final deletedAt = lease['deleted_at'];
        if (status == 'active' && deletedAt == null) {
          activeLease = lease;
          break; // premier bail actif — cas rare d'en avoir plusieurs
        }
      }
    }

    String? tenantName;
    String? rentLabel;
    String? leaseId;
    int? rentHcCents;

    if (activeLease != null) {
      leaseId = activeLease['id'] as String?;

      final tenant = activeLease['tenant'] as Map<String, dynamic>?;
      if (tenant != null) {
        final firstName = tenant['first_name'] as String? ?? '';
        final lastName = tenant['last_name'] as String? ?? '';
        tenantName = '$firstName $lastName'.trim();
        if (tenantName.isEmpty) tenantName = null;
      }

      final rentCents = activeLease['rent_amount_cents'] as int?;
      final chargesCents = activeLease['charges_amount_cents'] as int?;
      if (rentCents != null) {
        final total = rentCents + (chargesCents ?? 0);
        rentLabel = '${MoneyFormat.formatEurosFromCents(total)} CC / mois';
        rentHcCents = rentCents;
      }
    }

    return PropertyListItem(
      property: Property.fromJson(json),
      activeLeaseId: leaseId,
      currentTenantName: tenantName,
      currentRentLabel: rentLabel,
      currentRentHcCents: rentHcCents,
    );
  }
}
