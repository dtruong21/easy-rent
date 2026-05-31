import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db.dart';
import '../../../core/utils/edge_function_error_mapper.dart';
import '../domain/receipt.dart';
import '../domain/receipt_generation_result.dart';

export '../../../core/utils/postgrest_error_mapper.dart' show mapPostgrestError;

final _log = Logger('ReceiptsRepository');

/// Contrat public du repository quittances.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class ReceiptsRepository {
  /// Liste toutes les quittances d'un bail, triées par [period_start DESC].
  ///
  /// Inclut les quittances annulées ([isVoided] = true) — filtrables côté UI.
  Future<List<Receipt>> listForLease(String leaseId);

  /// Retourne une quittance par son [id].
  ///
  /// Lance [ReceiptNotFoundException] si la RLS retourne 0 ligne.
  Future<Receipt> getById(String id);

  /// Génère une quittance via l'Edge Function `generate-receipt`.
  ///
  /// Mode 1 — via liste de paiements : [paymentIds] non null.
  /// Mode 2 — via période : [leaseId], [periodStart], [periodEnd] non null.
  ///
  /// Lance [ProfileIncompleteException] si le profil bailleur est incomplet
  /// (Edge Function retourne 422 `profile_incomplete`).
  /// Lance [FunctionException] pour les autres erreurs HTTP.
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  });

  /// Génère une URL signée (5 min) pour accéder au PDF d'une quittance.
  ///
  /// Le chemin [pdfPath] est stocké dans [Receipt.pdfPath] —
  /// l'URL elle-même n'est jamais persistée côté client.
  Future<String> signedUrl(String pdfPath);

  /// Annule une quittance via la RPC `void_receipt`.
  ///
  /// [reason] : motif obligatoire 3-500 caractères (validé côté client ET DB).
  /// Lance [PostgrestException] si cross-user ou déjà annulée (ERRCODE P0002).
  Future<void> voidReceipt(String id, String reason);
}

/// Implémentation Supabase du [ReceiptsRepository].
class SupabaseReceiptsRepository implements ReceiptsRepository {
  const SupabaseReceiptsRepository();

  @override
  Future<List<Receipt>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final rows = await Db.from('receipts')
        .select()
        .eq('lease_id', leaseId)
        .order('period_start', ascending: false)
        .limit(200);
    return rows.map((r) => Receipt.fromJson(r)).toList();
  }

  @override
  Future<Receipt> getById(String id) async {
    _log.info('getById($id)');
    final rows = await Db.from('receipts').select().eq('id', id).limit(1);
    if (rows.isEmpty) {
      throw ReceiptNotFoundException(id);
    }
    return Receipt.fromJson(rows.first);
  }

  @override
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    _log.info('generate(paymentIds=$paymentIds, leaseId=$leaseId)');

    final body = <String, dynamic>{};
    if (paymentIds != null) {
      body['payment_ids'] = paymentIds;
    } else {
      assert(
        leaseId != null && periodStart != null && periodEnd != null,
        'Mode période : leaseId, periodStart et periodEnd sont requis',
      );
      body['lease_id'] = leaseId;
      body['period_start'] = _dateToSql(periodStart!);
      body['period_end'] = _dateToSql(periodEnd!);
    }

    // Db.invokeFunction injecte automatiquement le schéma actif dans le body.
    final response = await Db.invokeFunction('generate-receipt', body: body);

    if (response.data == null) {
      throw const ReceiptGenerationException(
        'Réponse vide de l\'Edge Function generate-receipt',
      );
    }

    final data = response.data as Map<String, dynamic>;
    return ReceiptGenerationResult.fromJson(data);
  }

  @override
  Future<String> signedUrl(String pdfPath) async {
    _log.info('signedUrl(pdfPath=$pdfPath)');
    final url = await Supabase.instance.client.storage
        .from('receipts')
        .createSignedUrl(pdfPath, 300);
    return url;
  }

  @override
  Future<void> voidReceipt(String id, String reason) async {
    _log.info('voidReceipt(id=$id)');
    await Db.rpc('void_receipt', params: {'p_id': id, 'p_reason': reason});
  }

  // ---------------------------------------------------------------------------
  // Helpers privés
  // ---------------------------------------------------------------------------

  static String _dateToSql(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Exception levée quand une quittance est introuvable (RLS ou id inconnu).
class ReceiptNotFoundException implements Exception {
  const ReceiptNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'ReceiptNotFoundException: quittance $id introuvable';
}

/// Exception levée lors d'un échec inattendu de la génération.
class ReceiptGenerationException implements Exception {
  const ReceiptGenerationException(this.message);

  final String message;

  @override
  String toString() => 'ReceiptGenerationException: $message';
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider exposant le repository quittances.
final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  return const SupabaseReceiptsRepository();
});
