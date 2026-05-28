import 'dart:async';

import 'package:flutter/foundation.dart';

/// [ChangeNotifier] qui notifie [GoRouter.refreshListenable] à chaque
/// événement émis par un [Stream] (typiquement `client.auth.onAuthStateChange`).
///
/// Pattern standard pour connecter un Stream Dart à GoRouter :
/// https://pub.dev/packages/go_router#refreshing-with-a-stream
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
