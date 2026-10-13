import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/subscription_repository.dart';

final _log = Logger('ManageSubscriptionController');

/// Pilote la résiliation/réactivation de l'abonnement Pro (FEAT-044f).
///
/// `AsyncNotifier<void>` — même style que [CheckoutController]
/// (`checkout_controller.dart`) : `state` porte loading/erreur pour piloter
/// le bouton (désactivé pendant l'appel réseau). En cas d'échec, `state.error`
/// contient l'exception domaine levée par [SubscriptionRepository]
/// ([NoActiveWebSubscriptionException] / [SubscriptionUnauthenticatedException]
/// / [SubscriptionException]) — la vue s'en sert pour choisir le message de
/// la snackbar.
///
/// Ne réécrit PAS Firestore lui-même : l'état affiché (`proWillRenew`,
/// `proExpiresAt`) suit `landlordTierProvider`, mis à jour côté serveur par
/// le webhook RevenueCat (lag assumé, cf. plan §R2 — confirmation optimiste
/// côté UI via la snackbar de succès).
class ManageSubscriptionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Résilie l'abonnement (`cancel_at_period_end=true`).
  ///
  /// Retourne `true` en cas de succès (y compris `noop` idempotent côté
  /// serveur), `false` sinon — l'appelant lit alors `state.error` pour
  /// afficher le message adapté.
  Future<bool> cancel() =>
      _run(() => ref.read(subscriptionRepositoryProvider).cancel());

  /// Réactive l'abonnement (annule une résiliation programmée).
  Future<bool> reactivate() =>
      _run(() => ref.read(subscriptionRepositoryProvider).reactivate());

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await action();
      _log.info('manageSubscription action succeeded');
    });
    if (state.hasError) {
      _log.warning('manageSubscription action failed', state.error);
    }
    return !state.hasError;
  }
}

final manageSubscriptionControllerProvider =
    AsyncNotifierProvider<ManageSubscriptionController, void>(
      ManageSubscriptionController.new,
    );
