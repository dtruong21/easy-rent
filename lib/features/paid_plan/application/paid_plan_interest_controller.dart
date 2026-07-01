import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/paid_plan_interest_repository.dart';

final _log = Logger('PaidPlanInterestController');

/// Gère le clic « M'avertir du lancement » (footer simulateur + modal limite
/// atteinte tier FREE). `AsyncValue<void>` — `data` = succès, `error` =
/// échec affichable en snackbar.
class PaidPlanInterestController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> notifyMe({required List<String> features, String? email}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(paidPlanInterestRepositoryProvider)
          .markInterest(features: features, email: email);
      _log.info('markInterest OK (features=$features)');
    });
  }
}

final paidPlanInterestControllerProvider =
    AsyncNotifierProvider<PaidPlanInterestController, void>(
      PaidPlanInterestController.new,
    );
