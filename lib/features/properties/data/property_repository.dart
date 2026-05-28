import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db.dart';
import '../domain/property.dart';
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
  });

  /// Met à jour les champs métier d'un bien existant.
  ///
  /// Seuls `name`, `address`, `type`, `surface_m2` sont inclus dans le payload.
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
  }) async {
    _log.info('create(type=${type.sqlValue})');
    // Ne PAS inclure landlord_id : la RLS WITH CHECK le fixe à auth.uid().
    // Ne PAS inclure created_at / updated_at / deleted_at : gérés par triggers.
    final payload = <String, dynamic>{
      'name': name.trim(),
      'address': address.trim(),
      'type': type.sqlValue,
      'surface_m2': surfaceM2,
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
