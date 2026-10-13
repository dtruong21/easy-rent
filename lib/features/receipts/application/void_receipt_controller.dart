import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/receipts_repository.dart';
import '../domain/receipt_action_error.dart';
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
      final code = switch (e.code) {
        'permission-denied' ||
        'unauthenticated' => ReceiptActionError.permissionDenied,
        'not-found' => ReceiptActionError.receiptNotFound,
        'failed-precondition' => ReceiptActionError.alreadyVoidedOrInvalid,
        _ => ReceiptActionError.voidFailed,
      };
      state = VoidReceiptError(message: code.name);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de void_receipt', e, st);
      state = VoidReceiptError(message: ReceiptActionError.unknown.name);
    }
  }

  void reset() => state = const VoidReceiptIdle();
}

/// Provider **keyé par `receiptId`** : chaque quittance de la liste a sa propre
/// instance d'état d'annulation.
///
/// Sans ce `family`, un provider global unique était partagé par toutes les
/// cartes/menus de quittance montés (grille et timeline). Au clic « annuler »,
/// l'état `submitting` désactivait le bouton sur CHAQUE ligne, et le
/// `ref.listen` de chaque widget monté déclenchait un SnackBar au succès — un
/// par ligne. La clé isole l'état par quittance.
final voidReceiptControllerProvider = StateNotifierProvider.autoDispose
    .family<VoidReceiptController, VoidReceiptState, String>(
      (ref, _) => VoidReceiptController(ref),
    );
