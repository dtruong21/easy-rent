// ignore_for_file: use_null_aware_elements
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db.dart';
import '../domain/heating_type.dart';
import '../domain/property.dart';
import '../domain/property_list_item.dart';
import '../domain/property_type.dart';

export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;

final _log = Logger('PropertyRepository');

/// Contrat public du repository biens immobiliers.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class PropertyRepository {
  /// Liste tous les biens du landlord courant, triés `created_at DESC`.
  ///
  /// Limité à 200 lignes (garde-fou — cible utilisateur : 1-20 biens).
  /// RLS filtre automatiquement par `auth.uid()` et `deleted_at IS NULL`.
  Future<List<Property>> list();

  /// Liste les biens avec jointure sur les baux actifs.
  ///
  /// Retourne des [PropertyListItem] enrichis : locataire courant, loyer CC,
  /// identifiant du bail actif. Utilisé pour la vue cards/table Phase 2.
  ///
  /// Filtrage client-side : `status='active' AND deleted_at IS NULL`.
  /// Limité à 200 biens (même garde-fou que [list]).
  Future<List<PropertyListItem>> listWithLeases();

  /// Retourne un bien par son [id].
  ///
  /// Lance [PropertyNotFoundException] si la RLS renvoie 0 ligne
  /// (bien archivé, non possédé, ou id inconnu).
  Future<Property> getById(String id);

  /// Crée un nouveau bien.
  ///
  /// Ne pas inclure `landlord_id` dans les champs — la RLS (`properties_insert_own`)
  /// le gère côté serveur. Ne pas inclure `created_at`, `updated_at`, `deleted_at`.
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator,
    bool furnished,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    // FEAT-017 — Financement & acquisition
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  });

  /// Met à jour les champs métier d'un bien existant.
  ///
  /// Tous les champs métier (y compris les nouveaux) sont inclus dans le payload.
  /// Le trigger `tr_02_set_updated_at` mettra à jour `updated_at` automatiquement.
  /// Le trigger `tr_01_prevent_protected_columns_change` bloque toute modification
  /// de `deleted_at` ou `created_at`.
  Future<Property> update(Property property);

  /// Compte les baux actifs liés au bien [propertyId].
  ///
  /// Utilisé avant archivage pour afficher un avertissement renforcé si > 0.
  Future<int> countActiveLeases(String propertyId);

  /// Archive (soft-delete) le bien [id] via la RPC `soft_delete_property`.
  ///
  /// L'UPDATE direct sur `deleted_at` est INTERDIT (trigger `tr_01_prevent_protected_columns_change`
  /// lèverait ERRCODE 42501). On doit obligatoirement passer par cette RPC SECURITY DEFINER.
  ///
  /// Si le bien n'appartient pas au user courant, la RPC ne fait rien (0 row affected)
  /// — considéré comme succès silencieux.
  Future<void> archive(String id);
}

/// Implémentation Supabase du [PropertyRepository].
class SupabasePropertyRepository implements PropertyRepository {
  const SupabasePropertyRepository();

  @override
  Future<List<Property>> list() async {
    _log.info('list()');
    final rows = await Db.from(
      'properties',
    ).select().order('created_at', ascending: false).limit(200);
    return rows.map((r) => Property.fromJson(r)).toList();
  }

  @override
  Future<List<PropertyListItem>> listWithLeases() async {
    _log.info('listWithLeases()');
    // Jointure sur la table leases via la FK leases_property_id_fkey.
    // On récupère tous les baux (filtre status='active' appliqué côté client
    // dans PropertyListItem.fromJson pour éviter un filtrage PostgREST sur la
    // jointure qui masquerait les biens sans bail).
    const leaseSelect =
        'id, rent_amount_cents, charges_amount_cents, status, deleted_at, '
        'tenant:tenants(id, first_name, last_name)';
    final rows = await Db.from('properties')
        .select('*, leases:leases!leases_property_id_fkey($leaseSelect)')
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map((r) => PropertyListItem.fromJson(r)).toList();
  }

  @override
  Future<Property> getById(String id) async {
    _log.info('getById($id)');
    final rows = await Db.from('properties').select().eq('id', id).limit(1);
    if (rows.isEmpty) {
      throw PropertyNotFoundException(id);
    }
    return Property.fromJson(rows.first);
  }

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  }) async {
    _log.info('create(type=${type.sqlValue})');
    // Ne PAS inclure landlord_id : la RLS WITH CHECK le fixe à auth.uid().
    // Ne PAS inclure created_at / updated_at / deleted_at : gérés par triggers.
    // Omettre proprement les champs null pour éviter d'écraser les DEFAULT SQL.
    final payload = <String, dynamic>{
      'name': name.trim(),
      'address': address.trim(),
      'type': type.sqlValue,
      if (surfaceM2 != null) 'surface_m2': surfaceM2,
      if (postalCode != null) 'postal_code': postalCode.trim(),
      if (city != null) 'city': city.trim(),
      if (rooms != null) 'rooms': rooms,
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (floor != null) 'floor': floor,
      'has_elevator': hasElevator,
      'furnished': furnished,
      if (heatingType != null) 'heating_type': heatingType.sqlValue,
      if (dpeLetter != null) 'dpe_letter': dpeLetter,
      if (dpeValueKwhM2Year != null) 'dpe_value_kwh_m2_year': dpeValueKwhM2Year,
      if (gesLetter != null) 'ges_letter': gesLetter,
      if (constructionYear != null) 'construction_year': constructionYear,
      // FEAT-017 — Financement & acquisition
      if (purchasePriceCents != null)
        'purchase_price_cents': purchasePriceCents,
      if (purchaseDate != null)
        'purchase_date': purchaseDate.toIso8601String().substring(0, 10),
      if (notaryFeesCents != null) 'notary_fees_cents': notaryFeesCents,
      'is_new_property': isNewProperty,
      if (propertyTaxAnnualCents != null)
        'property_tax_annual_cents': propertyTaxAnnualCents,
      if (insurancePnoAnnualCents != null)
        'insurance_pno_annual_cents': insurancePnoAnnualCents,
      if (condoFeesNonRecoverableCents != null)
        'condo_fees_non_recoverable_cents': condoFeesNonRecoverableCents,
      if (loanPrincipalCents != null)
        'loan_principal_cents': loanPrincipalCents,
      if (loanRateBps != null) 'loan_rate_bps': loanRateBps,
      if (loanInsuranceBps != null) 'loan_insurance_bps': loanInsuranceBps,
      if (loanDurationMonths != null)
        'loan_duration_months': loanDurationMonths,
      if (loanStartDate != null)
        'loan_start_date': loanStartDate.toIso8601String().substring(0, 10),
      if (loanMonthlyPaymentOverrideCents != null)
        'loan_monthly_payment_override_cents': loanMonthlyPaymentOverrideCents,
    };
    final rows = await Db.from('properties').insert(payload).select();
    return Property.fromJson(rows.first);
  }

  @override
  Future<Property> update(Property property) async {
    _log.info('update(id=${property.id})');
    // Seuls les champs métier — JAMAIS created_at, updated_at, deleted_at.
    final payload = <String, dynamic>{
      'name': property.name.trim(),
      'address': property.address.trim(),
      'type': property.type.sqlValue,
      'surface_m2': property.surfaceM2,
      'postal_code': property.postalCode,
      'city': property.city,
      'rooms': property.rooms,
      'bedrooms': property.bedrooms,
      'floor': property.floor,
      'has_elevator': property.hasElevator,
      'furnished': property.furnished,
      'heating_type': property.heatingType?.sqlValue,
      'dpe_letter': property.dpeLetter,
      'dpe_value_kwh_m2_year': property.dpeValueKwhM2Year,
      'ges_letter': property.gesLetter,
      'construction_year': property.constructionYear,
      // FEAT-017 — Financement & acquisition
      'purchase_price_cents': property.purchasePriceCents,
      'purchase_date': property.purchaseDate?.toIso8601String().substring(
        0,
        10,
      ),
      'notary_fees_cents': property.notaryFeesCents,
      'is_new_property': property.isNewProperty,
      'property_tax_annual_cents': property.propertyTaxAnnualCents,
      'insurance_pno_annual_cents': property.insurancePnoAnnualCents,
      'condo_fees_non_recoverable_cents': property.condoFeesNonRecoverableCents,
      'loan_principal_cents': property.loanPrincipalCents,
      'loan_rate_bps': property.loanRateBps,
      'loan_insurance_bps': property.loanInsuranceBps,
      'loan_duration_months': property.loanDurationMonths,
      'loan_start_date': property.loanStartDate?.toIso8601String().substring(
        0,
        10,
      ),
      'loan_monthly_payment_override_cents':
          property.loanMonthlyPaymentOverrideCents,
    };
    final rows = await Db.from(
      'properties',
    ).update(payload).eq('id', property.id).select();
    if (rows.isEmpty) {
      throw PropertyNotFoundException(property.id);
    }
    return Property.fromJson(rows.first);
  }

  @override
  Future<int> countActiveLeases(String propertyId) async {
    _log.info('countActiveLeases($propertyId)');
    final rows = await Db.from('leases')
        .select('id')
        .eq('property_id', propertyId)
        .eq('status', 'active')
        .filter('deleted_at', 'is', null)
        .limit(1);
    // Retourne 0 ou 1 — seul "y en a-t-il au moins un" est consommé par l'UI.
    return rows.length;
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    // L'UPDATE direct sur deleted_at est bloqué par le trigger
    // `tr_01_prevent_protected_columns_change_properties` (ERRCODE 42501).
    // On passe OBLIGATOIREMENT par la RPC SECURITY DEFINER.
    await Db.rpc('soft_delete_property', params: {'p_id': id});
  }
}

/// Exception levée quand un bien est introuvable (RLS ou archivage).
class PropertyNotFoundException implements Exception {
  const PropertyNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'PropertyNotFoundException: bien $id introuvable';
}

/// Provider exposant le repository biens immobiliers.
final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  return const SupabasePropertyRepository();
});
