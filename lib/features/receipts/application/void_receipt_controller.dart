import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/receipts_repository.dart';
import 'lease_receipts_provider.dart';

final _log = Logger('VoidReceiptController');

/// État du flow d'annulation d'une quittance.
sealed class VoidReceiptState {
  const VoidReceiptState();
}

/// Au repos — prêt à recevoir une action.
final class VoidReceiptIdle extends VoidReceiptState {
  const VoidReceiptIdle();
}

/// Annulation en cours — bouton désactivé.
final class VoidReceiptSubmitting extends VoidReceiptState {
  const VoidReceiptSubmitting();
}

/// Annulation réussie.
final class VoidReceiptSuccess extends VoidReceiptState {
  const VoidReceiptSuccess();
}

/// Erreur lors de l'annulation.
final class VoidReceiptError extends VoidReceiptState {
  const VoidReceiptError({required this.message});
  final String message;
}

/// Contrôle le flow d'annulation d'une quittance.
///
/// Appelle la RPC `void_receipt` via [ReceiptsRepository.voidReceipt].
/// Sur succès : invalide [leaseReceiptsProvider(leaseId)] pour rafraîchir la liste.
class VoidReceiptController extends StateNotifier<VoidReceiptState> {
  VoidReceiptController(this._ref) : super(const VoidReceiptIdle());

  final Ref _ref;

  /// Annule la quittance [receiptId] avec le motif [reason].
  ///
  /// [leaseId] : requis pour invalider le cache liste après succès.
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
      _log.info('receipt voided id=$receiptId');
      state = const VoidReceiptSuccess();
    } on PostgrestException catch (e, st) {
      _log.warning('PostgrestException lors de void_receipt', e, st);
      state = VoidReceiptError(message: mapPostgrestError(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de void_receipt', e, st);
      state = const VoidReceiptError(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const VoidReceiptIdle();
}

/// Provider autoDispose du contrôleur d'annulation de quittance.
final voidReceiptControllerProvider =
    StateNotifierProvider.autoDispose<VoidReceiptController, VoidReceiptState>(
      (ref) => VoidReceiptController(ref),
    );
