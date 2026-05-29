import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db.dart';
import '../domain/lease.dart';
import '../domain/lease_list_item.dart';

export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;

final _log = Logger('LeaseRepository');

/// Contrat public du repository baux.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class LeaseRepository {
  /// Liste tous les baux du landlord courant, joints avec property + tenant
  /// pour l'affichage.
  ///
  /// Tri : `status ASC` (active d'abord) puis `start_date DESC`.
  /// Limité à 200 lignes. RLS filtre par `auth.uid()` et `deleted_at IS NULL`.
  Future<List<LeaseListItem>> listForDisplay();

  /// Retourne un bail par son [id].
  ///
  /// Lance [LeaseNotFoundException] si la RLS renvoie 0 ligne.
  Future<Lease> getById(String id);

  /// Crée un nouveau bail.
  ///
  /// Ne pas inclure `landlord_id` (géré par RLS), ni `status` (default SQL
  /// `active`), ni timestamps.
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
  });

  /// Met à jour les champs métier d'un bail existant.
  ///
  /// Le statut n'est PAS modifiable via cette méthode — utiliser [close] pour
  /// passer de `active` à `terminated`.
  Future<Lease> update(Lease lease);

  /// Clôture un bail actif : status → `terminated`, end_date = [effectiveEndDate].
  ///
  /// Lance [LeaseAlreadyClosedException] si le bail n'est plus actif.
  /// Atomique : filtre `status='active'` dans l'UPDATE.
  Future<Lease> close(String id, {required DateTime effectiveEndDate});

  /// Retourne `true` si un bail actif (autre que [excludeLeaseId]) existe
  /// pour ce [propertyId].
  ///
  /// Utilisé pour l'avertissement "Ce bien a déjà un bail actif" avant
  /// create / update.
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  });

  /// Archive (soft-delete) le bail [id] via la RPC `soft_delete_lease`.
  ///
  /// L'UPDATE direct sur `deleted_at` est INTERDIT (trigger
  /// `tr_01_prevent_protected_columns_change` lèverait ERRCODE 42501).
  Future<void> archive(String id);
}

/// Implémentation Supabase du [LeaseRepository].
class SupabaseLeaseRepository implements LeaseRepository {
  const SupabaseLeaseRepository();

  @override
  Future<List<LeaseListItem>> listForDisplay() async {
    _log.info('listForDisplay()');
    final rows = await Db.from('leases')
        .select(
          '*, property:properties(id, name), tenant:tenants(id, first_name, last_name)',
        )
        .order('status', ascending: true) // active (a) avant terminated (t)
        .order('start_date', ascending: false) // plus récent en premier
        .limit(200);
    return rows.map((r) => LeaseListItem.fromJson(r)).toList();
  }

  @override
  Future<Lease> getById(String id) async {
    _log.info('getById($id)');
    final rows = await Db.from('leases').select().eq('id', id).limit(1);
    if (rows.isEmpty) {
      throw LeaseNotFoundException(id);
    }
    return Lease.fromJson(rows.first);
  }

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    _log.info('create(propertyId=$propertyId, tenantId=$tenantId)');
    // Ne PAS inclure landlord_id : la RLS WITH CHECK le fixe à auth.uid().
    // Ne PAS inclure status : default SQL 'active'.
    // Ne PAS inclure created_at / updated_at / deleted_at : gérés par triggers.
    final payload = <String, dynamic>{
      'property_id': propertyId,
      'tenant_id': tenantId,
      'rent_amount_cents': rentAmountCents,
      'charges_amount_cents': chargesAmountCents,
      'start_date': _dateToSql(startDate),
      if (endDate != null) 'end_date': _dateToSql(endDate),
    };
    final rows = await Db.from('leases').insert(payload).select();
    return Lease.fromJson(rows.first);
  }

  @override
  Future<Lease> update(Lease lease) async {
    _log.info('update(id=${lease.id})');
    // Seuls les champs métier — JAMAIS landlord_id, status, timestamps, deleted_at.
    final payload = <String, dynamic>{
      'property_id': lease.propertyId,
      'tenant_id': lease.tenantId,
      'rent_amount_cents': lease.rentAmountCents,
      'charges_amount_cents': lease.chargesAmountCents,
      'start_date': _dateToSql(lease.startDate),
      'end_date': lease.endDate != null ? _dateToSql(lease.endDate!) : null,
    };
    final rows = await Db.from(
      'leases',
    ).update(payload).eq('id', lease.id).select();
    if (rows.isEmpty) {
      throw LeaseNotFoundException(lease.id);
    }
    return Lease.fromJson(rows.first);
  }

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async {
    _log.info('close(id=$id)');
    // Filtre `status='active'` pour atomicité (race-condition safe).
    // Si la ligne n'existe plus ou est déjà clôturée → 0 row → exception.
    final rows = await Db.from('leases')
        .update({
          'status': 'terminated',
          'end_date': _dateToSql(effectiveEndDate),
        })
        .eq('id', id)
        .eq('status', 'active')
        .select();
    if (rows.isEmpty) {
      throw LeaseAlreadyClosedException(id);
    }
    return Lease.fromJson(rows.first);
  }

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async {
    _log.info(
      'hasOtherActiveLeaseOnProperty($propertyId, exclude=$excludeLeaseId)',
    );
    var query = Db.from('leases')
        .select('id')
        .eq('property_id', propertyId)
        .eq('status', 'active')
        .filter('deleted_at', 'is', null);

    // Exclure le bail courant côté serveur (mode édition).
    if (excludeLeaseId != null) {
      query = query.neq('id', excludeLeaseId);
    }

    final rows = await query.limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    // L'UPDATE direct sur deleted_at est bloqué par le trigger
    // `tr_01_prevent_protected_columns_change_leases` (ERRCODE 42501).
    // On passe OBLIGATOIREMENT par la RPC SECURITY DEFINER.
    await Db.rpc('soft_delete_lease', params: {'p_id': id});
  }

  // ---------------------------------------------------------------------------
  // Helpers privés
  // ---------------------------------------------------------------------------

  /// Convertit un [DateTime] en chaîne `YYYY-MM-DD` pour Postgres `date`.
  static String _dateToSql(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Exception levée quand un bail est introuvable (RLS ou archivage).
class LeaseNotFoundException implements Exception {
  const LeaseNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'LeaseNotFoundException: bail $id introuvable';
}

/// Exception levée lors d'une tentative de clôture d'un bail déjà clôturé.
class LeaseAlreadyClosedException implements Exception {
  const LeaseAlreadyClosedException(this.id);

  final String id;

  @override
  String toString() =>
      'LeaseAlreadyClosedException: bail $id déjà clôturé ou introuvable';
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider exposant le repository baux.
final leaseRepositoryProvider = Provider<LeaseRepository>((ref) {
  return const SupabaseLeaseRepository();
});
