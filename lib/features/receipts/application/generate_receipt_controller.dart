import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/receipts_repository.dart';
import '../domain/receipt_generation_state.dart';
import 'lease_receipts_provider.dart';

final _log = Logger('GenerateReceiptController');

class GenerateReceiptController extends StateNotifier<ReceiptGenerationState> {
  GenerateReceiptController(this._ref)
    : super(const ReceiptGenerationState.idle());

  final Ref _ref;

  Future<void> submitFromPayment({
    required String paymentId,
    required String leaseId,
  }) async {
    await _generate(paymentIds: [paymentId], leaseId: leaseId);
  }

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

  void reset() => state = const ReceiptGenerationState.idle();

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

      _ref.invalidate(leaseReceiptsProvider(leaseId));

      _log.info('receipt generated id=${result.receiptId}');
      state = ReceiptGenerationState.success(result: result);
    } on ProfileIncompleteException catch (e, st) {
      _log.warning('Profil incomplet lors de la génération', e, st);
      state = ReceiptGenerationState.profileIncomplete(missing: e.missing);
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning(
        'FirebaseFunctionsException génération (code=${e.code})',
        e,
        st,
      );
      final msg = switch (e.code) {
        'permission-denied' || 'unauthenticated' => 'Action non autorisée.',
        'failed-precondition' =>
          'Aucun paiement trouvé pour cette période ou bail invalide.',
        'not-found' => 'Bail ou paiements introuvables.',
        _ => 'Erreur lors de la génération du PDF. Veuillez réessayer.',
      };
      state = ReceiptGenerationState.error(message: msg);
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

final generateReceiptControllerProvider =
    StateNotifierProvider.autoDispose<
      GenerateReceiptController,
      ReceiptGenerationState
    >((ref) => GenerateReceiptController(ref));
