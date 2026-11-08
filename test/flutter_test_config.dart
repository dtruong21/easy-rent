import 'dart:async';

import 'package:easyrent/core/config/store_billing.dart';

/// Config globale de la suite : `flutter_test` simule Android par défaut, ce
/// qui ferait passer [isStoreApp] à vrai. On force le comportement web
/// (parcours Stripe) pour que les tests existants restent valides ; les tests
/// « app store » posent `debugIsStoreAppOverride = true` et le remettent à
/// `false` en `tearDown`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugIsStoreAppOverride = false;
  await testMain();
}
