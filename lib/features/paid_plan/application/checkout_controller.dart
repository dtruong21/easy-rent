import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/checkout_repository.dart';

final _log = Logger('CheckoutController');

class CheckoutController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String?> startCheckout({required String plan}) async {
    state = const AsyncLoading();
    String? url;
    state = await AsyncValue.guard(() async {
      url = await ref
          .read(checkoutRepositoryProvider)
          .createCheckoutSession(plan: plan);
      _log.info('Checkout session created (plan=$plan)');
    });
    return state.hasError ? null : url;
  }
}

final checkoutControllerProvider =
    AsyncNotifierProvider<CheckoutController, void>(CheckoutController.new);
