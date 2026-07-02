import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/receipts_repository.dart';
import 'lease_receipts_provider.dart';
import '../../dashboard/application/dashboard_provider.dart';

final _log = Logger('VoidReceiptController');

/// État du flow d'annulation d'une quittance.
sealed class VoidReceiptState {
  const VoidReceiptState();
}

final class VoidReceiptIdle extends VoidReceiptState {
  const VoidReceiptIdle();
}

final class VoidReceiptSubmitting extends VoidReceiptState {
  const VoidReceiptSubmitting();
}

final class VoidReceiptSuccess extends VoidReceiptState {
  const VoidReceiptSuccess();
}

final class VoidReceiptError extends VoidReceiptState {
  const VoidReceiptError({required this.message});
  final String message;
}

/// Contrôle le flow d'annulation d'une quittance.
///
/// Appelle la Callable `voidReceipt` via [ReceiptsRepository.voidReceipt].
class VoidReceiptController extends StateNotifier<VoidReceiptState> {
  VoidReceiptController(this._ref) : super(const VoidReceiptIdle());

  final Ref _ref;

  Future<void> voidReceipt({
    required String receiptId,
    required String reason,
    required String leaseId,
  }) async {
    state = const VoidReceiptSubmitting();

    try {
      await _ref
          .read(receiptsRepositoryProvider)
          .voidReceipt(receiptId, reason);

      _ref.invalidate(leaseReceiptsProvider(leaseId));
      _ref.invalidate(dashboardProvider);
      _log.info('receipt voided id=$receiptId');
      state = const VoidReceiptSuccess();
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning(
        'FirebaseFunctionsException voidReceipt (code=${e.code})',
        e,
        st,
      );
      final msg = switch (e.code) {
        'permission-denied' || 'unauthenticated' => 'Action non autorisée.',
        'not-found' => 'Quittance introuvable.',
        'failed-precondition' =>
          'La quittance est déjà annulée ou ne peut pas être annulée.',
        _ => 'Erreur lors de l\'annulation. Veuillez réessayer.',
      };
      state = VoidReceiptError(message: msg);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de void_receipt', e, st);
      state = const VoidReceiptError(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  void reset() => state = const VoidReceiptIdle();
}

final voidReceiptControllerProvider =
    StateNotifierProvider.autoDispose<VoidReceiptController, VoidReceiptState>(
      (ref) => VoidReceiptController(ref),
    );
