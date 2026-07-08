import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/receipts_repository.dart';
import '../domain/receipt_action_error.dart';
import '../domain/receipt_generation_state.dart';
import 'lease_receipts_provider.dart';
import '../../dashboard/application/dashboard_provider.dart';

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
      // La Callable generateReceipt exige TOUJOURS leaseId (requireString,
      // receipts.ts) — y compris avec paymentIds, dont elle vérifie la
      // cohérence (p.leaseId == leaseId). L'omettre en mode paymentIds
      // faisait échouer toute génération depuis la fiche bail en
      // invalid-argument (« leaseId must be a non-empty string »),
      // bug découvert en E2E le 2026-07-02.
      final result = await repo.generate(
        paymentIds: paymentIds,
        leaseId: leaseId,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );

      _ref.invalidate(leaseReceiptsProvider(leaseId));
      _ref.invalidate(dashboardProvider);

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
      final code = switch (e.code) {
        'permission-denied' ||
        'unauthenticated' => ReceiptActionError.permissionDenied,
        'failed-precondition' => ReceiptActionError.noPaymentForPeriod,
        'not-found' => ReceiptActionError.leaseOrPaymentsNotFound,
        _ => ReceiptActionError.generationFailed,
      };
      state = ReceiptGenerationState.error(message: code.name);
    } on ReceiptGenerationException catch (e, st) {
      _log.warning('ReceiptGenerationException', e, st);
      state = ReceiptGenerationState.error(
        message: ReceiptActionError.generationFailed.name,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de la génération', e, st);
      state = ReceiptGenerationState.error(
        message: ReceiptActionError.unknown.name,
      );
    }
  }
}

final generateReceiptControllerProvider =
    StateNotifierProvider.autoDispose<
      GenerateReceiptController,
      ReceiptGenerationState
    >((ref) => GenerateReceiptController(ref));
