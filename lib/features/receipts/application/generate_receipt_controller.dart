import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/edge_function_error_mapper.dart';
import '../data/receipts_repository.dart';
import '../domain/receipt_generation_state.dart';
import 'lease_receipts_provider.dart';

final _log = Logger('GenerateReceiptController');

/// Contrôle le flow de génération d'une quittance.
///
/// Transitions d'état :
/// idle → submitting → success(result) | error(msg) | profileIncomplete(missing)
///
/// Sur succès : invalide [leaseReceiptsProvider(leaseId)] pour rafraîchir la
/// liste des quittances.
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux usages du bouton.
class GenerateReceiptController extends StateNotifier<ReceiptGenerationState> {
  GenerateReceiptController(this._ref)
    : super(const ReceiptGenerationState.idle());

  final Ref _ref;

  /// Génère une quittance depuis un paiement individuel.
  ///
  /// [paymentId] : identifiant du paiement source.
  /// [leaseId] : bail parent — requis pour l'invalidation du cache.
  Future<void> submitFromPayment({
    required String paymentId,
    required String leaseId,
  }) async {
    await _generate(paymentIds: [paymentId], leaseId: leaseId);
  }

  /// Génère une quittance depuis une période (mode lease+période).
  ///
  /// [leaseId] : bail concerné.
  /// [periodStart], [periodEnd] : bornes de la période.
  Future<void> submitFromPeriod({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    await _generate(
      leaseId: leaseId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  /// Remet le controller à l'état idle (ex. : après fermeture du dialog).
  void reset() => state = const ReceiptGenerationState.idle();

  // ---------------------------------------------------------------------------
  // Implémentation interne
  // ---------------------------------------------------------------------------

  Future<void> _generate({
    List<String>? paymentIds,
    required String leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    state = const ReceiptGenerationState.submitting();

    try {
      final repo = _ref.read(receiptsRepositoryProvider);
      final result = await repo.generate(
        paymentIds: paymentIds,
        leaseId: paymentIds != null ? null : leaseId,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );

      // Invalider la liste pour afficher la nouvelle quittance.
      _ref.invalidate(leaseReceiptsProvider(leaseId));

      _log.info('receipt generated id=${result.receiptId}');
      state = ReceiptGenerationState.success(result: result);
    } on ProfileIncompleteException catch (e, st) {
      _log.warning('Profil incomplet lors de la génération', e, st);
      state = ReceiptGenerationState.profileIncomplete(missing: e.missing);
    } on FunctionException catch (e, st) {
      _log.warning('FunctionException lors de la génération', e, st);
      // mapEdgeFunctionError peut relancer ProfileIncompleteException.
      try {
        final msg = mapEdgeFunctionError(e);
        state = ReceiptGenerationState.error(message: msg);
      } on ProfileIncompleteException catch (pie, _) {
        state = ReceiptGenerationState.profileIncomplete(missing: pie.missing);
      }
    } on ReceiptGenerationException catch (e, st) {
      _log.warning('ReceiptGenerationException', e, st);
      state = const ReceiptGenerationState.error(
        message: 'Erreur lors de la génération du PDF. Veuillez réessayer.',
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de la génération', e, st);
      state = const ReceiptGenerationState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }
}

/// Provider autoDispose du contrôleur de génération de quittance.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du bouton.
final generateReceiptControllerProvider =
    StateNotifierProvider.autoDispose<
      GenerateReceiptController,
      ReceiptGenerationState
    >((ref) => GenerateReceiptController(ref));
