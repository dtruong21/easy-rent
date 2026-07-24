import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Contrat testable de gestion de l'abonnement Baillan Pro (FEAT-044f) —
/// wrappe la callable `manageSubscription(action)` (europe-west1). Calque
/// exact de [CheckoutRepository] (`checkout_repository.dart`) : interface
/// fine, implémentation Firebase injectée via provider, jamais
/// `FirebaseFunctions.instance` en dur dans les consommateurs.
abstract interface class SubscriptionRepository {
  /// Programme la résiliation (`cancel_at_period_end=true` côté Stripe).
  ///
  /// Idempotent côté serveur (`status:'noop'` si déjà programmé, cf. plan
  /// §5) — ne lève rien dans ce cas, l'appel est simplement un no-op.
  Future<void> cancel();

  /// Annule une résiliation programmée (`cancel_at_period_end=false`).
  /// Idempotent côté serveur (noop si déjà renouvelable).
  Future<void> reactivate();
}

class FirebaseSubscriptionRepository implements SubscriptionRepository {
  FirebaseSubscriptionRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<void> cancel() => _call('cancel');

  @override
  Future<void> reactivate() => _call('reactivate');

  Future<void> _call(String action) async {
    final callable = _functions.httpsCallable(
      'manageSubscription',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    try {
      await callable.call<Map<String, dynamic>>({'action': action});
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// Mappe les codes du contrat backend (plan FEAT-044f §Backend, table
  /// « Cas d'erreur ») vers une erreur domaine — la callable brute
  /// ([FirebaseFunctionsException]) ne doit jamais fuiter au-delà de cette
  /// couche (même discipline que `FirestoreReceiptsRepository.generate`).
  Exception _mapError(FirebaseFunctionsException e) {
    if (e.code == 'failed-precondition' &&
        (e.message?.contains('no_active_web_subscription') ?? false)) {
      return const NoActiveWebSubscriptionException();
    }
    if (e.code == 'unauthenticated') {
      return const SubscriptionUnauthenticatedException();
    }
    return SubscriptionException(
      'manageSubscription failed (code=${e.code}): ${e.message}',
    );
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => FirebaseSubscriptionRepository(
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  ),
);

/// Levée quand la callable répond `failed-precondition` /
/// `no_active_web_subscription` — aucun abonnement Stripe actif trouvé pour
/// cet utilisateur (abonné mobile mal étiqueté, abonnement déjà expiré...).
/// Cas prévu par le contrat backend (plan §R5) : l'UI n'affiche le bouton
/// que pour un abonnement présumé web, ce cas ne devrait donc survenir
/// qu'en course rare (expiration concurrente).
class NoActiveWebSubscriptionException implements Exception {
  const NoActiveWebSubscriptionException();
  @override
  String toString() => 'NoActiveWebSubscriptionException';
}

/// Levée quand la callable répond `unauthenticated` (session expirée ou
/// absente).
class SubscriptionUnauthenticatedException implements Exception {
  const SubscriptionUnauthenticatedException();
  @override
  String toString() => 'SubscriptionUnauthenticatedException';
}

/// Erreur générique (réseau, panne Stripe, code non mappé...).
class SubscriptionException implements Exception {
  const SubscriptionException(this.message);
  final String message;
  @override
  String toString() => 'SubscriptionException: $message';
}
