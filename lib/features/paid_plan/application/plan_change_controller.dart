import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/subscription_repository.dart';

final _log = Logger('PlanChangeController');

/// Pilote le changement de palier en libre-service (FEAT-056 §4.4,
/// `SubscriptionRepository.changePlan`).
///
/// `AsyncNotifier<void>` — même style que [ManageSubscriptionController]
/// (`manage_subscription_controller.dart`) : `state` porte loading/erreur
/// pour piloter le bouton de confirmation du dialog de changement d'offre. En
/// cas d'échec, `state.error` contient l'exception domaine levée par
/// [SubscriptionRepository] ([NoActiveWebSubscriptionException] /
/// [PriceNotConfiguredException] / [SubscriptionUnauthenticatedException] /
/// [SubscriptionException]) — la vue s'en sert pour choisir le message de la
/// snackbar (§8.4 : `planChangeErrorNoWebSub`, `planChangeErrorPriceUnavailable`,
/// `planChangeErrorGeneric`).
///
/// Ne réécrit PAS Firestore lui-même : le palier affiché suit
/// `landlordTierProvider`, mis à jour côté serveur par le webhook RevenueCat
/// (lag assumé, confirmation optimiste via la snackbar de succès).
class PlanChangeController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Retourne `true` en cas de succès (y compris `noop` idempotent côté
  /// serveur), `false` sinon — l'appelant lit alors `state.error`.
  Future<bool> changePlan({
    required String level,
    required String period,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(subscriptionRepositoryProvider)
          .changePlan(level: level, period: period);
      _log.info('changePlan succeeded (level=$level, period=$period)');
    });
    if (state.hasError) {
      _log.warning('changePlan failed', state.error);
    }
    return !state.hasError;
  }
}

final planChangeControllerProvider =
    AsyncNotifierProvider<PlanChangeController, void>(PlanChangeController.new);
