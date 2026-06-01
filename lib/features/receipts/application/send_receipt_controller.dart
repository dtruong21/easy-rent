import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/edge_function_error_mapper.dart';
import '../data/receipts_repository.dart';
import '../domain/receipt.dart';
import '../domain/send_receipt_state.dart';
import 'lease_receipts_provider.dart';

final _log = Logger('SendReceiptController');

/// Contrôle le flow d'envoi d'une quittance par email.
///
/// Transitions d'état :
/// - idle → submitting → success(sentAt, sentToEmail)
/// - idle → confirmingResend (si déjà envoyée) → submitting → success
/// - submitting → error(message)
/// - submitting → tenantNoEmail
/// - submitting → rateLimited
///
/// Sur succès : invalide [leaseReceiptsProvider(leaseId)] pour rafraîchir la
/// liste des quittances.
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux usages du bouton.
class SendReceiptController extends StateNotifier<SendReceiptState> {
  SendReceiptController(this._ref) : super(const SendReceiptState.idle());

  final Ref _ref;

  /// Initie l'envoi de la quittance.
  ///
  /// Si [receipt.hasBeenSent], passe en état [confirmingResend] et attend
  /// la confirmation de l'utilisateur (via [confirmResend]).
  /// Sinon, déclenche directement [_send].
  Future<void> initiate({
    required Receipt receipt,
    required String leaseId,
  }) async {
    if (receipt.hasBeenSent) {
      _log.info('receipt ${receipt.id} déjà envoyé — demande confirmation');
      state = SendReceiptState.confirmingResend(
        previousSentAt: receipt.sentAt!,
        previousMaskedEmail: receipt.maskedSentToEmail ?? '***',
      );
      return;
    }
    await _send(receipt: receipt, leaseId: leaseId);
  }

  /// Confirme le renvoi après dialog de confirmation.
  ///
  /// Appelé lorsque l'utilisateur accepte dans [ConfirmResendDialog].
  Future<void> confirmResend({
    required Receipt receipt,
    required String leaseId,
  }) async {
    await _send(receipt: receipt, leaseId: leaseId);
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const SendReceiptState.idle();

  // ---------------------------------------------------------------------------
  // Implémentation interne
  // ---------------------------------------------------------------------------

  Future<void> _send({
    required Receipt receipt,
    required String leaseId,
  }) async {
    state = const SendReceiptState.submitting();

    try {
      final repo = _ref.read(receiptsRepositoryProvider);
      final updated = await repo.sendReceipt(receiptId: receipt.id);

      // Invalider la liste pour afficher sentAt mis à jour.
      _ref.invalidate(leaseReceiptsProvider(leaseId));

      _log.info('receipt ${receipt.id} envoyé');
      state = SendReceiptState.success(
        sentAt: updated.sentAt ?? DateTime.now(),
        sentToEmail: updated.sentToEmail ?? '',
      );
    } on TenantNoEmailException catch (e, st) {
      _log.warning('TenantNoEmailException lors de sendReceipt', e, st);
      state = const SendReceiptState.tenantNoEmail();
    } on EmailQuotaExceededException catch (e, st) {
      _log.warning('EmailQuotaExceededException lors de sendReceipt', e, st);
      state = const SendReceiptState.rateLimited();
    } on ReceiptInvalidForSendException catch (e, st) {
      _log.warning('ReceiptInvalidForSendException lors de sendReceipt', e, st);
      state = const SendReceiptState.error(
        message: 'Quittance annulée ou périmée — impossible à envoyer.',
      );
    } on PdfUnavailableException catch (e, st) {
      _log.warning('PdfUnavailableException lors de sendReceipt', e, st);
      state = const SendReceiptState.error(
        message: 'PDF indisponible — régénérez la quittance.',
      );
    } on ReceiptSendException catch (e, st) {
      _log.warning('ReceiptSendException lors de sendReceipt', e, st);
      state = SendReceiptState.error(message: e.message);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de sendReceipt', e, st);
      state = const SendReceiptState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }
}

/// Provider autoDispose du contrôleur d'envoi de quittance par email.
///
/// [autoDispose] garantit un state propre entre deux utilisations du bouton.
final sendReceiptControllerProvider =
    StateNotifierProvider.autoDispose<SendReceiptController, SendReceiptState>(
      (ref) => SendReceiptController(ref),
    );
