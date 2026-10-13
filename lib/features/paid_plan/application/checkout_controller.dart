import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/checkout_repository.dart';

final _log = Logger('CheckoutController');

class CheckoutController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Lance une session Stripe Checkout pour [level]/[period] (FEAT-056 §4.2).
  ///
  /// Retourne l'URL Stripe hébergée en cas de succès, `null` en cas d'échec —
  /// l'appelant lit alors `state.error` pour choisir le message (mappé via
  /// [CheckoutRepository]'s domain exceptions : [AlreadySubscribedException],
  /// [LevelNotPurchasableException], [PriceNotConfiguredException],
  /// [CheckoutException]).
  Future<String?> startCheckout({
    required String level,
    required String period,
  }) async {
    state = const AsyncLoading();
    String? url;
    state = await AsyncValue.guard(() async {
      url = await ref
          .read(checkoutRepositoryProvider)
          .createCheckoutSession(level: level, period: period);
      _log.info('Checkout session created (level=$level, period=$period)');
    });
    if (state.hasError) {
      _log.warning('startCheckout failed', state.error);
    }
    return state.hasError ? null : url;
  }
}

final checkoutControllerProvider =
    AsyncNotifierProvider<CheckoutController, void>(CheckoutController.new);
