import '../../../core/utils/french_date.dart';
import 'tenant.dart';

/// Modèle composé pour l'affichage de la liste des locataires.
///
/// Résultat d'une jointure PostgREST :
/// ```
/// select('*, leases:leases!leases_tenant_id_fkey(
///   id, status, deleted_at, start_date, end_date, rent_amount_cents,
///   property:properties(id, name))')
/// ```
///
/// Non-freezed — sérialisation manuelle depuis le JSON imbriqué.
/// Pas de logique métier ici — juste la projection d'affichage.
class TenantListItem {
  const TenantListItem({
    required this.tenant,
    this.activeLeaseId,
    this.currentPropertyName,
    this.activeLeasePeriodLabel,
    this.activeLeaseRentCents,
    this.currentPropertyId,
    this.currentPropertyColorKey,
  });

  /// Le locataire complet (tous les champs scalaires).
  final Tenant tenant;

  /// Identifiant du bail actif, ou `null` si sans bail.
  final String? activeLeaseId;

  /// Nom du bien occupé, ou `null` si sans bail.
  final String? currentPropertyName;

  /// Période du bail formatée en français, ou `null` si sans bail.
  ///
  /// - Sans date de fin : "Depuis dd/MM/yyyy"
  /// - Avec date de fin : "dd/MM/yyyy → dd/MM/yyyy"
  final String? activeLeasePeriodLabel;

  /// Loyer du bail actif en centimes, ou `null` si sans bail.
  final int? activeLeaseRentCents;

  /// Identifiant du bien occupé, ou `null` si sans bail.
  ///
  /// Nécessaire au repli déterministe de `PropertyColorKey.resolve` quand
  /// [currentPropertyColorKey] est absent.
  final String? currentPropertyId;

  /// Clé de palette [PropertyColorKey] du bien occupé (`properties.colorKey`
  /// brut, potentiellement `null`), ou `null` si sans bail — cf.
  /// `lib/core/ui/theme/property_color.dart`. Résolue via une lecture
  /// groupée de `properties`, jamais une requête par locataire (cf.
  /// `TenantRepository.listWithActiveLeases`).
  final String? currentPropertyColorKey;

  /// Construit un [TenantListItem] depuis le JSON brut de PostgREST.
  ///
  /// La clé `leases` contient une liste de baux (jointure 1-N).
  /// On filtre `status='active' AND deleted_at IS NULL` côté client.
  /// Si plusieurs baux actifs existent, on prend le plus récent par `start_date`.
  factory TenantListItem.fromJson(Map<String, dynamic> json) {
    final leasesRaw = json['leases'] as List<dynamic>?;

    Map<String, dynamic>? activeLease;
    DateTime? activeLeaseStartDate;

    if (leasesRaw != null) {
      for (final raw in leasesRaw) {
        final lease = raw as Map<String, dynamic>;
        final status = lease['status'] as String?;
        final deletedAt = lease['deleted_at'];
        if (status == 'active' && deletedAt == null) {
          // Prendre le plus récent par start_date si plusieurs baux actifs.
          final startStr = lease['start_date'] as String?;
          final startDate = startStr != null
              ? DateTime.tryParse(startStr)
              : null;
          if (activeLease == null ||
              (startDate != null &&
                  activeLeaseStartDate != null &&
                  startDate.isAfter(activeLeaseStartDate))) {
            activeLease = lease;
            activeLeaseStartDate = startDate;
          }
        }
      }
    }

    String? leaseId;
    String? propertyName;
    String? periodLabel;
    int? rentCents;

    if (activeLease != null) {
      leaseId = activeLease['id'] as String?;
      rentCents = activeLease['rent_amount_cents'] as int?;

      final property = activeLease['property'] as Map<String, dynamic>?;
      if (property != null) {
        propertyName = property['name'] as String?;
      }

      final startStr = activeLease['start_date'] as String?;
      final endStr = activeLease['end_date'] as String?;
      if (startStr != null) {
        final startLabel = FrenchDate.formatIsoString(startStr);
        if (endStr == null) {
          periodLabel = 'Depuis $startLabel';
        } else {
          final endLabel = FrenchDate.formatIsoString(endStr);
          periodLabel = '$startLabel → $endLabel';
        }
      }
    }

    return TenantListItem(
      tenant: Tenant.fromJson(json),
      activeLeaseId: leaseId,
      currentPropertyName: propertyName,
      activeLeasePeriodLabel: periodLabel,
      activeLeaseRentCents: rentCents,
    );
  }
}
