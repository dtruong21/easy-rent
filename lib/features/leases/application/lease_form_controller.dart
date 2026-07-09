import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../payments/domain/payment_method.dart';
import '../../dashboard/application/dashboard_provider.dart';
import '../../properties/application/properties_list_provider.dart';
import '../../tenants/application/tenants_list_provider.dart';
import '../data/lease_repository.dart';
import '../domain/charge_mode.dart';
import '../domain/lease.dart';
import '../domain/lease_form_state.dart';
import '../domain/lease_submit_error.dart';
import '../domain/lease_type.dart';
import 'lease_detail_provider.dart';
import 'leases_list_provider.dart';

final _log = Logger('LeaseFormController');

/// Contrôle le formulaire de création / édition d'un bail.
///
/// Distingue create ([initial] == null) et update ([initial] != null).
/// Sur succès : invalide [leasesListProvider] et, en mode édition,
/// [leaseDetailProvider(id)] pour que la liste et la fiche soient à jour.
///
/// Méthode séparée [close] pour la clôture (flow distinct de l'édition).
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux ouvertures
/// du formulaire.
class LeaseFormController extends StateNotifier<LeaseFormState> {
  LeaseFormController(this._ref) : super(const LeaseFormState.idle());

  final Ref _ref;

  /// Soumet le formulaire (création ou édition).
  ///
  /// [initial] : null pour une création, bail existant pour une édition.
  Future<void> submit({
    Lease? initial,
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType = LeaseType.unfurnished,
    ChargeMode? chargeMode,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
    int nonRecoverableChargesCents = 0,
  }) async {
    state = const LeaseFormState.submitting();

    try {
      final repo = _ref.read(leaseRepositoryProvider);
      final Lease result;

      if (initial == null) {
        // Mode création
        result = await repo.create(
          propertyId: propertyId,
          tenantId: tenantId,
          rentAmountCents: rentAmountCents,
          chargesAmountCents: chargesAmountCents,
          startDate: startDate,
          endDate: endDate,
          leaseType: leaseType,
          chargeMode: chargeMode,
          depositAmountCents: depositAmountCents,
          paymentDay: paymentDay,
          paymentMethod: paymentMethod,
          irlIndexValue: irlIndexValue,
          irlQuarterRef: irlQuarterRef,
          agencyFeesCents: agencyFeesCents,
          solidarityClause: solidarityClause,
          entryInventoryDone: entryInventoryDone,
          nonRecoverableChargesCents: nonRecoverableChargesCents,
        );
        _log.info('lease created id=${result.id}');
      } else {
        // Mode édition — on applique les modifications sur le modèle existant
        final updated = initial.copyWith(
          propertyId: propertyId,
          tenantId: tenantId,
          rentAmountCents: rentAmountCents,
          chargesAmountCents: chargesAmountCents,
          startDate: startDate,
          endDate: endDate,
          leaseType: leaseType,
          chargeMode: chargeMode,
          depositAmountCents: depositAmountCents,
          paymentDay: paymentDay,
          paymentMethod: paymentMethod,
          irlIndexValue: irlIndexValue,
          irlQuarterRef: irlQuarterRef,
          agencyFeesCents: agencyFeesCents,
          solidarityClause: solidarityClause,
          entryInventoryDone: entryInventoryDone,
          nonRecoverableChargesCents: nonRecoverableChargesCents,
        );
        result = await repo.update(updated);
        _log.info('lease updated id=${result.id}');
        // Invalider la fiche pour forcer un rechargement.
        _ref.invalidate(leaseDetailProvider(result.id));
      }

      // Invalider la liste pour afficher le nouveau/modifié bail.
      _ref.invalidate(leasesListProvider);
      // Un bail change le statut des cards biens (Loué/Vacant, locataire,
      // loyer denormalisés) et locataires (Actif/Sans bail) + le dashboard.
      _ref.invalidate(propertiesListItemsProvider);
      _ref.invalidate(tenantsListItemsProvider);
      _ref.invalidate(dashboardProvider);

      state = LeaseFormState.success(lease: result);
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseException lors de submit', e, st);
      state = LeaseFormState.error(message: _mapFirebaseError(e).name);
    } on LeaseNotFoundException catch (notFound, st) {
      _log.warning('LeaseNotFoundException lors de submit', notFound, st);
      state = LeaseFormState.error(message: LeaseSubmitError.notFound.name);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = LeaseFormState.error(message: LeaseSubmitError.unknown.name);
    }
  }

  /// Clôture un bail actif : status → `terminated`, end_date = [effectiveEndDate].
  ///
  /// Distinct de [submit] : pas de re-validation des champs métier, juste
  /// le changement de statut avec la date effective.
  Future<void> close({
    required String leaseId,
    required DateTime effectiveEndDate,
  }) async {
    state = const LeaseFormState.submitting();

    try {
      final repo = _ref.read(leaseRepositoryProvider);
      final result = await repo.close(
        leaseId,
        effectiveEndDate: effectiveEndDate,
      );
      _ref.invalidate(leasesListProvider);
      _ref.invalidate(leaseDetailProvider(leaseId));
      state = LeaseFormState.success(lease: result);
    } on LeaseAlreadyClosedException catch (alreadyClosed, st) {
      _log.warning(
        'LeaseAlreadyClosedException lors de close',
        alreadyClosed,
        st,
      );
      state = LeaseFormState.error(
        message: LeaseSubmitError.alreadyClosed.name,
      );
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseException lors de close', e, st);
      state = LeaseFormState.error(message: _mapFirebaseError(e).name);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de close', e, st);
      state = LeaseFormState.error(message: LeaseSubmitError.unknown.name);
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const LeaseFormState.idle();

  LeaseSubmitError _mapFirebaseError(FirebaseFunctionsException e) {
    final code = e.code;
    final msg = e.message ?? '';
    if (msg.contains('property not owned') ||
        msg.contains('tenant not owned')) {
      return LeaseSubmitError.propertyOrTenantNotOwned;
    }
    if (msg.contains('property is deleted') ||
        msg.contains('tenant is deleted')) {
      return LeaseSubmitError.propertyOrTenantArchived;
    }
    // FEAT-044 : plafond free-tier de baux actifs (createLease/updateLease).
    if (code == 'resource-exhausted' || msg.contains('lease_limit_reached')) {
      return LeaseSubmitError.limitReached;
    }
    if (code == 'permission-denied' || code == 'unauthenticated') {
      return LeaseSubmitError.permissionDenied;
    }
    if (code == 'failed-precondition') {
      return LeaseSubmitError.invalidState;
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return LeaseSubmitError.serviceUnavailable;
    }
    return LeaseSubmitError.saveFailed;
  }
}

/// Provider autoDispose du contrôleur de formulaire bail.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final leaseFormControllerProvider =
    StateNotifierProvider.autoDispose<LeaseFormController, LeaseFormState>(
      (ref) => LeaseFormController(ref),
    );
