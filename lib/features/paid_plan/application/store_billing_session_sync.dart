import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/store_billing.dart';
import '../../auth/application/auth_session_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/session_state.dart';
import '../data/store_billing_service.dart';

final _log = Logger('StoreBillingSessionSync');

/// Aligne l'utilisateur RevenueCat sur la session Firebase (FEAT-044e) :
/// `logIn(uid)` pour un compte COMPLET uniquement, `logOut()` en le quittant.
/// Jamais de `logIn` pour un anonyme : son achat serait rattaché à un uid que
/// la purge des anonymes supprime. Configure le service au premier état reçu.
/// Les appels sont sérialisés : un `logOut` ne double jamais un `logIn` en
/// cours.
class StoreBillingSessionSync {
  StoreBillingSessionSync(this._service);

  final StoreBillingService _service;
  Future<void> _queue = Future.value();
  bool _configured = false;
  String? _loggedInUid;

  Future<void> onSession(SessionState state, String? uid) {
    final target = state == SessionState.fullyAuthenticated ? uid : null;
    return _queue = _queue.then((_) => _apply(target)).catchError((
      Object e,
      StackTrace st,
    ) {
      _log.warning('synchronisation RevenueCat échouée', e, st);
    });
  }

  Future<void> _apply(String? target) async {
    if (!_configured) {
      _configured = true;
      await _service.configure();
    }
    if (target == _loggedInUid) return;
    if (target == null) {
      await _service.logOut();
    } else {
      await _service.logIn(target);
    }
    _loggedInUid = target;
  }
}

/// Branche [StoreBillingSessionSync] sur [sessionStateProvider]. Inerte
/// (aucun appel au SDK) tant que l'achat intégré est coupé. Gardé vivant par
/// `BaillanApp`.
final storeBillingSessionSyncProvider = Provider<void>((ref) {
  if (!isInAppPurchaseEnabled) return;
  final sync = StoreBillingSessionSync(ref.watch(storeBillingServiceProvider));
  ref.listen<SessionState>(sessionStateProvider, (_, state) {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    unawaited(sync.onSession(state, uid));
  }, fireImmediately: true);
});
