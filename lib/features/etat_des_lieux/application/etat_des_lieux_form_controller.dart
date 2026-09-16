import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/etat_des_lieux_repository.dart';
import '../domain/edl_enums.dart';
import '../domain/etat_des_lieux.dart';

final _log = Logger('EtatDesLieuxFormController');

// ---------------------------------------------------------------------------
// État sealed
// ---------------------------------------------------------------------------

/// Motif d'échec de la création d'un état des lieux — indépendant de la
/// locale d'affichage (FEAT-037).
///
/// [EtatDesLieuxFormController] (sans `BuildContext`) reste une fonction
/// pure : il détermine le motif mais ne compose aucun message traduit. La
/// couche présentation ([EtatDesLieuxFormPage]) mappe cet enum vers
/// `context.l10n.<clé>` (patron `UpdateCategoryErrorReasonL10n` /
/// `ProfileFormErrorReasonL10n`, cf. `lib/l10n/l10n_convention.dart`).
enum EdlFormErrorReason {
  /// Profil bailleur incomplet (nom/adresse manquants) — la CF
  /// `createEtatDesLieux` refuse de figer des parties incomplètes
  /// (`profile_incomplete`, décret 2016-382).
  profileIncomplete,

  /// Le bail ciblé n'appartient pas au bailleur courant (`lease not owned`).
  leaseNotOwned,

  /// Erreur réseau/backend ou inattendue.
  generic,
}

/// État du flow de création d'un état des lieux.
sealed class EdlFormState {
  const EdlFormState();
}

/// Au repos.
final class EdlFormIdle extends EdlFormState {
  const EdlFormIdle();
}

/// Création en cours.
final class EdlFormSubmitting extends EdlFormState {
  const EdlFormSubmitting();
}

/// Création réussie — [edl] est l'état des lieux créé (immuable, parties et
/// adresse figées côté serveur).
final class EdlFormSuccess extends EdlFormState {
  const EdlFormSuccess({required this.edl});
  final EtatDesLieux edl;
}

/// Erreur lors de la création.
final class EdlFormError extends EdlFormState {
  const EdlFormError({required this.reason});
  final EdlFormErrorReason reason;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Contrôle le flow de création d'un état des lieux.
///
/// Appelle [EtatDesLieuxRepository.create] (callable `createEtatDesLieux`) et
/// mappe les refus métier connus vers un [EdlFormErrorReason].
class EtatDesLieuxFormController extends StateNotifier<EdlFormState> {
  EtatDesLieuxFormController(this._ref) : super(const EdlFormIdle());

  final Ref _ref;

  /// Crée l'état des lieux [type] du bail [leaseId], daté [date].
  ///
  /// `landlordFullName`/`landlordAddress`/`tenantFullName`/`propertyAddress`
  /// ne sont PAS des paramètres : ils sont dérivés et figés côté serveur.
  Future<void> submit({
    required String leaseId,
    required EtatDesLieuxType type,
    required DateTime date,
    required List<EdlRoom> rooms,
    required EdlMeterReadings meterReadings,
    required int keysCount,
    String? generalComment,
  }) async {
    state = const EdlFormSubmitting();

    try {
      final edl = await _ref
          .read(etatDesLieuxRepositoryProvider)
          .create(
            leaseId: leaseId,
            type: type,
            date: date,
            rooms: rooms,
            meterReadings: meterReadings,
            keysCount: keysCount,
            generalComment: generalComment,
          );

      _log.info('EDL créé id=${edl.id} leaseId=$leaseId type=${type.sqlValue}');
      state = EdlFormSuccess(edl: edl);
    } on FirebaseFunctionsException catch (e, st) {
      // Refus métier attendus : à tester AVANT FirebaseException (dont
      // FirebaseFunctionsException hérite).
      if (e.message?.contains('profile_incomplete') == true) {
        _log.info(
          'createEtatDesLieux refusé (profile_incomplete) leaseId=$leaseId',
        );
        state = const EdlFormError(
          reason: EdlFormErrorReason.profileIncomplete,
        );
        return;
      }
      if (e.message?.contains('lease not owned') == true) {
        _log.info(
          'createEtatDesLieux refusé (lease not owned) leaseId=$leaseId',
        );
        state = const EdlFormError(reason: EdlFormErrorReason.leaseNotOwned);
        return;
      }
      _log.warning(
        'FirebaseFunctionsException lors de createEtatDesLieux',
        e,
        st,
      );
      state = const EdlFormError(reason: EdlFormErrorReason.generic);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de createEtatDesLieux', e, st);
      state = const EdlFormError(reason: EdlFormErrorReason.generic);
    }
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const EdlFormIdle();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider autoDispose du contrôleur de formulaire état des lieux.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final etatDesLieuxFormControllerProvider =
    StateNotifierProvider.autoDispose<EtatDesLieuxFormController, EdlFormState>(
      (ref) => EtatDesLieuxFormController(ref),
    );
