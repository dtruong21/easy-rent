import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Contrat testable — wrappe la callable `createCheckoutSession(level, period)`
/// (FEAT-056 §4.2).
///
/// **Nouvelle forme uniquement** : le serveur accepte toujours l'ancienne
/// forme `{plan}` pour les clients déjà déployés (shim de compatibilité côté
/// Functions), mais tout code client neuf envoie `{level, period}` — ne
/// jamais réintroduire `{plan}` ici.
abstract interface class CheckoutRepository {
  /// [level] : id de palier (`'pro'` | `'max'` | `'ultra'`).
  /// [period] : `'monthly'` | `'annual'`.
  Future<String> createCheckoutSession({
    required String level,
    required String period,
  });
}

class FirebaseCheckoutRepository implements CheckoutRepository {
  FirebaseCheckoutRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<String> createCheckoutSession({
    required String level,
    required String period,
  }) async {
    final callable = _functions.httpsCallable(
      'createCheckoutSession',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'level': level,
        'period': period,
      });
      final url = result.data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw StateError('createCheckoutSession returned no URL');
      }
      return url;
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// Mappe les codes d'erreur du contrat backend (FEAT-056 §4.3/§4.4) vers une
  /// erreur domaine — la callable brute ([FirebaseFunctionsException]) ne
  /// doit jamais fuiter au-delà de cette couche (même discipline que
  /// `FirebaseSubscriptionRepository._mapError`).
  Exception _mapError(FirebaseFunctionsException e) {
    final message = e.message ?? '';
    if (e.code == 'failed-precondition' &&
        message.contains('already_subscribed_use_change_plan')) {
      return const AlreadySubscribedException();
    }
    if (e.code == 'failed-precondition' &&
        message.contains('level_not_purchasable')) {
      return const LevelNotPurchasableException();
    }
    if (e.code == 'failed-precondition' &&
        message.contains('price_not_configured')) {
      return const PriceNotConfiguredException();
    }
    return CheckoutException(
      'createCheckoutSession failed (code=${e.code}): ${e.message}',
    );
  }
}

final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => FirebaseCheckoutRepository(
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  ),
);

/// Levée quand la callable répond `failed-precondition` /
/// `already_subscribed_use_change_plan` — un abonné actif a re-cliqué
/// « S'abonner » au lieu de passer par le changement de palier en
/// libre-service (`SubscriptionRepository.changePlan`). Défense en
/// profondeur : l'UI ne doit déjà plus proposer ce chemin à un abonné actif.
class AlreadySubscribedException implements Exception {
  const AlreadySubscribedException();
  @override
  String toString() => 'AlreadySubscribedException';
}

/// Levée quand la callable répond `failed-precondition` /
/// `level_not_purchasable` — le palier ciblé est affiché mais pas encore
/// ouvert à la vente (Max/Ultra au lancement, FEAT-056 §2.3-b). Défense en
/// profondeur : l'UI ne doit déjà plus exposer de bouton de checkout pour un
/// palier non `purchasable`.
class LevelNotPurchasableException implements Exception {
  const LevelNotPurchasableException();
  @override
  String toString() => 'LevelNotPurchasableException';
}

/// Levée quand la callable répond `failed-precondition` /
/// `price_not_configured` — le price Stripe du palier/période ciblé n'est pas
/// encore configuré côté serveur (état transitoire attendu tant qu'un palier
/// nouvellement ouvert n'a pas ses 2 prix créés dans Stripe).
class PriceNotConfiguredException implements Exception {
  const PriceNotConfiguredException();
  @override
  String toString() => 'PriceNotConfiguredException';
}

/// Erreur générique (réseau, panne Stripe, code non mappé...).
class CheckoutException implements Exception {
  const CheckoutException(this.message);
  final String message;
  @override
  String toString() => 'CheckoutException: $message';
}
