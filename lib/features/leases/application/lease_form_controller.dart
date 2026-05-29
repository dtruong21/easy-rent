import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/lease_repository.dart';
import '../domain/lease.dart';
import '../domain/lease_form_state.dart';
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
        );
        result = await repo.update(updated);
        _log.info('lease updated id=${result.id}');
        // Invalider la fiche pour forcer un rechargement.
        _ref.invalidate(leaseDetailProvider(result.id));
      }

      // Invalider la liste pour afficher le nouveau/modifié bail.
      _ref.invalidate(leasesListProvider);

      state = LeaseFormState.success(lease: result);
    } on PostgrestException catch (e, st) {
      _log.warning('PostgrestException lors de submit', e, st);
      state = LeaseFormState.error(message: mapPostgrestError(e));
    } on LeaseNotFoundException catch (notFound, st) {
      _log.warning('LeaseNotFoundException lors de submit', notFound, st);
      state = const LeaseFormState.error(
        message: 'Bail introuvable. Il a peut-être été archivé.',
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = const LeaseFormState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
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
      state = const LeaseFormState.error(message: 'Ce bail est déjà clôturé.');
    } on PostgrestException catch (e, st) {
      _log.warning('PostgrestException lors de close', e, st);
      state = LeaseFormState.error(message: mapPostgrestError(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de close', e, st);
      state = const LeaseFormState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const LeaseFormState.idle();
}

/// Provider autoDispose du contrôleur de formulaire bail.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final leaseFormControllerProvider =
    StateNotifierProvider.autoDispose<LeaseFormController, LeaseFormState>(
      (ref) => LeaseFormController(ref),
    );
