import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/payment_repository.dart';
import '../../dashboard/application/dashboard_provider.dart';
import '../../leases/application/lease_detail_provider.dart';
import '../../leases/application/leases_list_provider.dart';
import '../domain/payment.dart';
import '../domain/payment_form_state.dart';
import '../domain/payment_method.dart';
import '../domain/payment_submit_error.dart';
import 'lease_payments_provider.dart';
import 'payment_detail_provider.dart';

final _log = Logger('PaymentFormController');

/// Contrôle le formulaire de création / édition d'un paiement.
///
/// Distingue create ([initial] == null) et update ([initial] != null).
/// Sur succès : invalide [leasePaymentsProvider(leaseId)] et, en mode édition,
/// [paymentDetailProvider(id)] pour que la liste et la fiche soient à jour.
///
/// Méthode séparée [archive] pour l'archivage (flow distinct de l'édition).
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux ouvertures
/// du formulaire.
class PaymentFormController extends StateNotifier<PaymentFormState> {
  PaymentFormController(this._ref) : super(const PaymentFormState.idle());

  final Ref _ref;

  /// Soumet le formulaire (création ou édition).
  ///
  /// [initial] : null pour une création, paiement existant pour une édition.
  /// [leaseId] : id du bail parent (requis pour l'invalidation du cache liste).
  /// [landlordId] : uid du landlord courant (requis pour l'INSERT).
  Future<void> submit({
    Payment? initial,
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
    state = const PaymentFormState.submitting();

    try {
      final repo = _ref.read(paymentRepositoryProvider);
      final Payment result;

      if (initial == null) {
        // Mode création
        result = await repo.create(
          leaseId: leaseId,
          landlordId: landlordId,
          periodStart: periodStart,
          periodEnd: periodEnd,
          paidAt: paidAt,
          rentAmountCents: rentAmountCents,
          chargesAmountCents: chargesAmountCents,
          paymentMethod: paymentMethod,
          notes: notes,
          reference: reference,
        );
        _log.info('payment created id=${result.id}');
      } else {
        // Mode édition — on applique les modifications sur le modèle existant
        final updated = initial.copyWith(
          periodStart: periodStart,
          periodEnd: periodEnd,
          paidAt: paidAt,
          rentAmountCents: rentAmountCents,
          chargesAmountCents: chargesAmountCents,
          paymentMethod: paymentMethod,
          notes: notes,
          reference: reference,
        );
        result = await repo.update(updated);
        _log.info('payment updated id=${result.id}');
        // Invalider la fiche pour forcer un rechargement.
        _ref.invalidate(paymentDetailProvider(result.id));
      }

      // Invalider la liste pour afficher le nouveau/modifié paiement.
      _ref.invalidate(leasePaymentsProvider(leaseId));
      _ref.invalidate(dashboardProvider);
      // Le statut « en retard » d'un bail est DÉRIVÉ de ses paiements
      // (`isLeaseLate()`, calculé dans `lease_repository`). Sans ces deux
      // invalidations, encaisser un paiement laissait le bail affiché « en
      // retard » jusqu'à un rechargement complet de la page, alors que le
      // dashboard — lui invalidé — était déjà à jour. Incohérence signalée en
      // recette le 2026-08-12.
      _ref.invalidate(leasesListProvider);
      _ref.invalidate(leaseDetailProvider(leaseId));

      state = PaymentFormState.success(payment: result);
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseException lors de submit', e, st);
      state = PaymentFormState.error(message: _mapFirebaseError(e).name);
    } on PaymentNotFoundException catch (notFound, st) {
      _log.warning('PaymentNotFoundException lors de submit', notFound, st);
      state = PaymentFormState.error(message: PaymentSubmitError.notFound.name);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = PaymentFormState.error(message: PaymentSubmitError.unknown.name);
    }
  }

  /// Archive (soft-delete) un paiement via la RPC `soft_delete_payment`.
  ///
  /// [leaseId] est requis pour invalider le cache liste après archivage.
  ///
  /// Le controller est partagé avec [PaymentFormPage] ; on ne veut PAS qu'une
  /// erreur résiduelle d'une session form précédente fuie dans le résultat de
  /// l'archive. `state = submitting` ci-dessous est suffisant pour éviter ça,
  /// mais on l'écrit explicitement pour rendre l'intention claire.
  Future<void> archive({
    required String paymentId,
    required String leaseId,
  }) async {
    state = const PaymentFormState.submitting();

    try {
      await _ref.read(paymentRepositoryProvider).archive(paymentId);
      _ref.invalidate(leasePaymentsProvider(leaseId));
      _ref.invalidate(paymentDetailProvider(paymentId));
      _ref.invalidate(dashboardProvider);
      // Archiver un paiement peut REMETTRE le bail en retard — même dérivation
      // que dans `submit`, donc mêmes invalidations, dans l'autre sens.
      _ref.invalidate(leasesListProvider);
      _ref.invalidate(leaseDetailProvider(leaseId));
      // Archive n'a pas de payload — on retombe sur idle.
      state = const PaymentFormState.idle();
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseException lors de archive', e, st);
      state = PaymentFormState.error(message: _mapFirebaseError(e).name);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de archive', e, st);
      state = PaymentFormState.error(message: PaymentSubmitError.unknown.name);
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const PaymentFormState.idle();

  PaymentSubmitError _mapFirebaseError(FirebaseFunctionsException e) {
    final code = e.code;
    if (code == 'permission-denied' || code == 'unauthenticated') {
      return PaymentSubmitError.permissionDenied;
    }
    if (code == 'failed-precondition') {
      return PaymentSubmitError.invalidState;
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return PaymentSubmitError.serviceUnavailable;
    }
    return PaymentSubmitError.saveFailed;
  }
}

/// Provider autoDispose du contrôleur de formulaire paiement.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final paymentFormControllerProvider =
    StateNotifierProvider.autoDispose<PaymentFormController, PaymentFormState>(
      (ref) => PaymentFormController(ref),
    );
