import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db.dart';
import '../domain/payment.dart';
import '../domain/payment_method.dart';

export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;

final _log = Logger('PaymentRepository');

/// Contrat public du repository paiements.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class PaymentRepository {
  /// Liste tous les paiements d'un bail, triés par [period_start DESC].
  ///
  /// RLS filtre par `auth.uid()` et `deleted_at IS NULL`.
  Future<List<Payment>> listForLease(String leaseId);

  /// Retourne un paiement par son [id].
  ///
  /// Lance [PaymentNotFoundException] si la RLS renvoie 0 ligne.
  Future<Payment> getById(String id);

  /// Crée un nouveau paiement.
  ///
  /// [landlordId] est passé explicitement car la policy `payments_insert_own`
  /// exige `landlord_id = auth.uid()`. Ne pas inclure `id` ni timestamps.
  Future<Payment> create({
    required String leaseId,
    required String landlordId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime paidAt,
    required int rentAmountCents,
    required int chargesAmountCents,
    required PaymentMethod paymentMethod,
    String? notes,
    String? reference,
  });

  /// Met à jour les champs métier d'un paiement existant.
  Future<Payment> update(Payment payment);

  /// Archive (soft-delete) le paiement [id] via la RPC `soft_delete_payment`.
  ///
  /// L'UPDATE direct sur `deleted_at` est INTERDIT (trigger
  /// `tr_01_prevent_protected_columns_change_payments` lèverait ERRCODE 42501).
  Future<void> archive(String id);
}

/// Implémentation Supabase du [PaymentRepository].
class SupabasePaymentRepository implements PaymentRepository {
  const SupabasePaymentRepository();

  @override
  Future<List<Payment>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final rows = await Db.from('payments')
        .select()
        .eq('lease_id', leaseId)
        .order('period_start', ascending: false)
        .limit(200);
    return rows.map((r) => Payment.fromJson(r)).toList();
  }

  @override
  Future<Payment> getById(String id) async {
    _log.info('getById($id)');
    final rows = await Db.from('payments').select().eq('id', id).limit(1);
    if (rows.isEmpty) {
      throw PaymentNotFoundException(id);
    }
    return Payment.fromJson(rows.first);
  }

  @override
  Future<Payment> create({
    required String leaseId,
    required String landlordId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime paidAt,
    required int rentAmountCents,
    required int chargesAmountCents,
    required PaymentMethod paymentMethod,
    String? notes,
    String? reference,
  }) async {
    _log.info('create(leaseId=$leaseId)');
    // landlord_id est inclus explicitement car la policy WITH CHECK l'exige.
    // Ne PAS inclure id, created_at, updated_at, deleted_at.
    final payload = <String, dynamic>{
      'lease_id': leaseId,
      'landlord_id': landlordId,
      'period_start': _dateToSql(periodStart),
      'period_end': _dateToSql(periodEnd),
      'paid_at': _dateToSql(paidAt),
      'rent_amount_cents': rentAmountCents,
      'charges_amount_cents': chargesAmountCents,
      'payment_method': paymentMethod.sqlValue,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    };
    final rows = await Db.from('payments').insert(payload).select();
    return Payment.fromJson(rows.first);
  }

  @override
  Future<Payment> update(Payment payment) async {
    _log.info('update(id=${payment.id})');
    // Seuls les champs métier — JAMAIS landlord_id, id, timestamps, deleted_at.
    final payload = <String, dynamic>{
      'period_start': _dateToSql(payment.periodStart),
      'period_end': _dateToSql(payment.periodEnd),
      'paid_at': _dateToSql(payment.paidAt),
      'rent_amount_cents': payment.rentAmountCents,
      'charges_amount_cents': payment.chargesAmountCents,
      'payment_method': payment.paymentMethod.sqlValue,
      'notes': payment.notes,
      'reference': payment.reference,
    };
    final rows = await Db.from(
      'payments',
    ).update(payload).eq('id', payment.id).select();
    if (rows.isEmpty) {
      throw PaymentNotFoundException(payment.id);
    }
    return Payment.fromJson(rows.first);
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    // L'UPDATE direct sur deleted_at est bloqué par le trigger
    // `tr_01_prevent_protected_columns_change_payments` (ERRCODE 42501).
    // On passe OBLIGATOIREMENT par la RPC SECURITY DEFINER.
    await Db.rpc('soft_delete_payment', params: {'p_id': id});
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

/// Exception levée quand un paiement est introuvable (RLS ou archivage).
class PaymentNotFoundException implements Exception {
  const PaymentNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'PaymentNotFoundException: paiement $id introuvable';
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider exposant le repository paiements.
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return const SupabasePaymentRepository();
});
