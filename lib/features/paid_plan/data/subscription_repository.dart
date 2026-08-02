import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'checkout_repository.dart'
    show LevelNotPurchasableException, PriceNotConfiguredException;

export 'checkout_repository.dart'
    show LevelNotPurchasableException, PriceNotConfiguredException;

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

  /// Change de palier en libre-service (FEAT-056 §4.4) — `action:
  /// 'change_plan'` de la même callable `manageSubscription`.
  ///
  /// Le client n'envoie **jamais** d'identifiant Stripe : le serveur résout
  /// l'abonnement à modifier via `metadata['rc_app_user_id'] == uid`
  /// (`pickManageableSubscription`, déjà IDOR-proof). Le changement est
  /// **immédiat et proraté** (montée facturée au prorata, descente créditée
  /// sur la facture suivante — jamais de remboursement) : l'UI appelante doit
  /// l'annoncer explicitement **avant** de confirmer (dialog dédié côté
  /// présentation, pas ici). N'applique rien côté Firestore elle-même — le
  /// palier reste accordé par le seul webhook RevenueCat (`PRODUCT_CHANGE`),
  /// même règle que `cancel`/`reactivate` (ADR 0002).
  ///
  /// Idempotent côté serveur : `status: 'noop'` si le price cible est déjà
  /// celui en cours (aucun appel Stripe, aucun event RC parasite) — ne lève
  /// rien dans ce cas.
  Future<void> changePlan({required String level, required String period});
}

class FirebaseSubscriptionRepository implements SubscriptionRepository {
  FirebaseSubscriptionRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<void> cancel() => _call('cancel');

  @override
  Future<void> reactivate() => _call('reactivate');

  @override
  Future<void> changePlan({required String level, required String period}) =>
      _call('change_plan', level: level, period: period);

  Future<void> _call(String action, {String? level, String? period}) async {
    final callable = _functions.httpsCallable(
      'manageSubscription',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    try {
      await callable.call<Map<String, dynamic>>({
        'action': action,
        'level': ?level,
        'period': ?period,
      });
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// Mappe les codes du contrat backend (plan FEAT-044f §Backend, table
  /// « Cas d'erreur ») vers une erreur domaine — la callable brute
  /// ([FirebaseFunctionsException]) ne doit jamais fuiter au-delà de cette
  /// couche (même discipline que `FirestoreReceiptsRepository.generate`).
  Exception _mapError(FirebaseFunctionsException e) {
    final message = e.message ?? '';
    if (e.code == 'failed-precondition' &&
        message.contains('no_active_web_subscription')) {
      return const NoActiveWebSubscriptionException();
    }
    if (e.code == 'failed-precondition' &&
        message.contains('price_not_configured')) {
      return const PriceNotConfiguredException();
    }
    if (e.code == 'failed-precondition' &&
        message.contains('level_not_purchasable')) {
      return const LevelNotPurchasableException();
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

/// [PriceNotConfiguredException] et [LevelNotPurchasableException] —
/// réutilisées telles quelles depuis `checkout_repository.dart` (`show`
/// ci-dessus) : `change_plan` et `createCheckoutSession` peuvent renvoyer
/// exactement les mêmes codes `failed-precondition`, une seule paire de
/// classes domaine suffit (sinon `pro_pricing_page.dart`, qui importe les
/// deux repositories, aurait un import ambigu).

/// Erreur générique (réseau, panne Stripe, code non mappé...).
class SubscriptionException implements Exception {
  const SubscriptionException(this.message);
  final String message;
  @override
  String toString() => 'SubscriptionException: $message';
}
