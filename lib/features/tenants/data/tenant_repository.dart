import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db.dart';
import '../domain/tenant.dart';

export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;

final _log = Logger('TenantRepository');

/// Contrat public du repository locataires.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class TenantRepository {
  /// Liste tous les locataires du landlord courant, triés `last_name ASC, first_name ASC`.
  ///
  /// Limité à 200 lignes (garde-fou — cible utilisateur : 1-50 locataires).
  /// RLS filtre automatiquement par `auth.uid()` et `deleted_at IS NULL`.
  Future<List<Tenant>> list();

  /// Retourne un locataire par son [id].
  ///
  /// Lance [TenantNotFoundException] si la RLS renvoie 0 ligne
  /// (locataire archivé, non possédé, ou id inconnu).
  Future<Tenant> getById(String id);

  /// Crée un nouveau locataire.
  ///
  /// Ne pas inclure `landlord_id` dans les champs — la RLS (`tenants_insert_own`)
  /// le gère côté serveur. Ne pas inclure `created_at`, `updated_at`, `deleted_at`.
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
  });

  /// Met à jour les champs métier d'un locataire existant.
  ///
  /// Seuls `first_name`, `last_name`, `email`, `phone` sont inclus dans le payload.
  /// Le trigger `tr_02_set_updated_at` mettra à jour `updated_at` automatiquement.
  /// Le trigger `tr_01_prevent_protected_columns_change` bloque toute modification
  /// de `deleted_at` ou `created_at`.
  Future<Tenant> update(Tenant tenant);

  /// Compte les baux actifs liés au locataire [tenantId].
  ///
  /// Utilisé avant archivage pour afficher un avertissement renforcé si > 0.
  Future<int> countActiveLeases(String tenantId);

  /// Archive (soft-delete) le locataire [id] via la RPC `soft_delete_tenant`.
  ///
  /// L'UPDATE direct sur `deleted_at` est INTERDIT (trigger `tr_01_prevent_protected_columns_change`
  /// lèverait ERRCODE 42501). On doit obligatoirement passer par cette RPC SECURITY DEFINER.
  ///
  /// Si le locataire n'appartient pas au user courant, la RPC ne fait rien (0 row affected)
  /// — considéré comme succès silencieux.
  Future<void> archive(String id);

  /// Retourne les baux liés au locataire [tenantId] (non-archivés).
  ///
  /// Retourne une liste de `Map<String, dynamic>` bruts —  le modèle `Lease` typé
  /// sera introduit en FEAT-005. À refactorer alors.
  ///
  /// Ordre : status DESC (active d'abord), start_date DESC.
  Future<List<Map<String, dynamic>>> listLeasesForTenant(String tenantId);
}

/// Implémentation Supabase du [TenantRepository].
class SupabaseTenantRepository implements TenantRepository {
  const SupabaseTenantRepository();

  @override
  Future<List<Tenant>> list() async {
    _log.info('list()');
    final rows = await Db.from('tenants')
        .select()
        .order('last_name', ascending: true)
        .order('first_name', ascending: true)
        .limit(200);
    return rows.map((r) => Tenant.fromJson(r)).toList();
  }

  @override
  Future<Tenant> getById(String id) async {
    _log.info('getById($id)');
    final rows = await Db.from('tenants').select().eq('id', id).limit(1);
    if (rows.isEmpty) {
      throw TenantNotFoundException(id);
    }
    return Tenant.fromJson(rows.first);
  }

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
  }) async {
    _log.info('create()');
    // Ne PAS inclure landlord_id : la RLS WITH CHECK le fixe à auth.uid().
    // Ne PAS inclure created_at / updated_at / deleted_at : gérés par triggers.
    // Ne pas logger email/firstName/lastName (PII).
    final payload = <String, dynamic>{
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'email': email.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    };
    final rows = await Db.from('tenants').insert(payload).select();
    return Tenant.fromJson(rows.first);
  }

  @override
  Future<Tenant> update(Tenant tenant) async {
    _log.info('update(id=${tenant.id})');
    // Seuls les champs métier — JAMAIS created_at, updated_at, deleted_at.
    // Ne pas logger email/firstName/lastName (PII).
    final payload = <String, dynamic>{
      'first_name': tenant.firstName.trim(),
      'last_name': tenant.lastName.trim(),
      'email': tenant.email.trim(),
      'phone': tenant.phone?.trim().isEmpty == true
          ? null
          : tenant.phone?.trim(),
    };
    final rows = await Db.from(
      'tenants',
    ).update(payload).eq('id', tenant.id).select();
    if (rows.isEmpty) {
      throw TenantNotFoundException(tenant.id);
    }
    return Tenant.fromJson(rows.first);
  }

  @override
  Future<int> countActiveLeases(String tenantId) async {
    _log.info('countActiveLeases($tenantId)');
    final rows = await Db.from('leases')
        .select('id')
        .eq('tenant_id', tenantId)
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
    // `tr_01_prevent_protected_columns_change_tenants` (ERRCODE 42501).
    // On passe OBLIGATOIREMENT par la RPC SECURITY DEFINER.
    await Db.rpc('soft_delete_tenant', params: {'p_id': id});
  }

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async {
    _log.info('listLeasesForTenant($tenantId)');
    // SELECT minimal pour l'affichage — sera remplacé par le modèle Lease en FEAT-005.
    // Tri par status ASCENDING : active (a) → archived (a) → terminated (t),
    // donc les baux actifs apparaissent en premier, puis archivés, puis résiliés.
    final rows = await Db.from('leases')
        .select(
          'id, property_id, start_date, end_date, status, rent_amount_cents',
        )
        .eq('tenant_id', tenantId)
        .filter('deleted_at', 'is', null)
        .order('status', ascending: true)
        .order('start_date', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }
}

/// Exception levée quand un locataire est introuvable (RLS ou archivage).
class TenantNotFoundException implements Exception {
  const TenantNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'TenantNotFoundException: locataire $id introuvable';
}

/// Provider exposant le repository locataires.
final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return const SupabaseTenantRepository();
});
